import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/src/crypto/crypto.dart'
    show InitialClientAuthMethod;
import 'package:dart_saltyrtc_client/src/logger.dart' show logger;
import 'package:dart_saltyrtc_client/src/messages/c2c/auth_initiator.dart'
    show AuthInitiator;
import 'package:dart_saltyrtc_client/src/messages/c2c/auth_responder.dart'
    show AuthResponder;
import 'package:dart_saltyrtc_client/src/messages/c2c/close.dart' show Close;
import 'package:dart_saltyrtc_client/src/messages/c2c/key.dart' show Key;
import 'package:dart_saltyrtc_client/src/messages/c2c/token.dart' show Token;
import 'package:dart_saltyrtc_client/src/messages/close_code.dart'
    show CloseCode;
import 'package:dart_saltyrtc_client/src/messages/id.dart' show Id, IdResponder;
import 'package:dart_saltyrtc_client/src/messages/message.dart'
    show MessageType;
import 'package:dart_saltyrtc_client/src/messages/message.dart' show Message;
import 'package:dart_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;
import 'package:dart_saltyrtc_client/src/messages/reader.dart'
    show MessageDecryptionExt;
import 'package:dart_saltyrtc_client/src/messages/s2c/new_responder.dart'
    show NewResponder;
import 'package:dart_saltyrtc_client/src/protocol/error.dart'
    show IgnoreMessageError, NoSharedTaskError, ProtocolError, ValidationError;
import 'package:dart_saltyrtc_client/src/protocol/peer.dart'
    show Client, Peer, Responder;
import 'package:dart_saltyrtc_client/src/protocol/phases/client_handshake.dart'
    show ClientHandshakePhase;
import 'package:dart_saltyrtc_client/src/protocol/phases/phase.dart'
    show
        InitiatorSendDropResponder,
        Phase,
        CommonAfterServerHandshake,
        ClientHandshakeInput,
        InitiatorIdentity;
import 'package:dart_saltyrtc_client/src/protocol/phases/task.dart'
    show TaskPhase;
import 'package:dart_saltyrtc_client/src/protocol/task.dart' show Task;

class ResponderWithState {
  final Responder responder;

  /// Used to identify the oldest responder during the path cleaning procedure.
  /// The client keeps a counter of how many responder connected.
  /// This is the value of that counter when this responder connected.
  final int counter;

  /// True if we have received a message from this client.
  bool receivedAnyMessage = false;

  /// State of the handshake with a specific responder.
  State state;

  ResponderWithState(
    this.responder, {
    required this.counter,
    required InitialClientAuthMethod authMethod,
  }) : state = State.waitForTokenMsg {
    final key = authMethod.trustedResponderSharedKey;
    if (key != null) {
      responder.setPermanentSharedKey(key);
      state = State.waitForKeyMsg;
    }
  }
}

/// State of the handshake with a specific responder.
enum State {
  waitForTokenMsg,
  waitForKeyMsg,
  waitForAuth,
}

class InitiatorClientHandshakePhase extends ClientHandshakePhase
    with InitiatorIdentity, InitiatorSendDropResponder {
  final Map<IdResponder, ResponderWithState> responders = {};

  /// Continuous incremental counter, used to track the oldest responder.
  ///
  /// Given of at least 2^53 (compiled to JS) id's this is more then enough
  /// for use to not worry about integer overflow.
  int responderCounter = 0;

  InitiatorClientHandshakePhase(
    CommonAfterServerHandshake common,
    ClientHandshakeInput input,
  ) : super(common, input);

  @override
  Peer getPeerWithId(Id id) {
    if (id.isServer()) return common.server;
    if (id.isResponder()) {
      final responder = responders[id];
      if (responder != null) {
        return responder.responder;
      } else {
        // this can happen when a responder has been dropped
        // but a message was still in flight.
        // we want to ignore this message but not to terminate the connection
        throw ValidationError(
          'Invalid responder id: $id',
          isProtocolError: false,
        );
      }
    }
    throw ProtocolError('Invalid peer id: $id');
  }

  @override
  void handleNewResponder(NewResponder msg) {
    addNewResponder(msg.id);
  }

  /// Adds a new responder the the container of known responders.
  void addNewResponder(IdResponder id) {
    // This will automatically override any previously set state.
    responders[id] = ResponderWithState(
      Responder(id, common.crypto),
      counter: responderCounter++,
      authMethod: input.authMethod,
    );

    // If we have more then this number of responders we drop the oldest.
    const responderSizeThreshold = 252;

    if (responders.length > responderSizeThreshold) {
      _dropOldestInactiveResponder();
    }
  }

  void _dropOldestInactiveResponder() {
    final responder = responders.entries
        .where((entry) => !entry.value.receivedAnyMessage)
        .fold<ResponderWithState?>(null, (min, entry) {
      final v = entry.value;
      if (min == null) {
        return v;
      }

      return min.counter < v.counter ? min : v;
    });

    if (responder != null) {
      dropResponder(responder.responder, CloseCode.droppedByInitiator);
    } else {
      // This can only happen if we have a bug in the client,
      // probably multiple bugs.
      throw AssertionError("Need but can't clean path.");
    }
  }

  @override
  Phase handleClientMessage(Uint8List msgBytes, Nonce nonce) {
    // Forced not null is ok as We know it's a known responder
    // or else the nonce validation would have failed.
    final responderWithState = responders[nonce.source.asResponder()]!;
    responderWithState.receivedAnyMessage = true;
    switch (responderWithState.state) {
      case State.waitForTokenMsg:
        return _handleWaitForToken(responderWithState, msgBytes, nonce);
      case State.waitForKeyMsg:
        return _handleWaitForKey(responderWithState, msgBytes, nonce);
      case State.waitForAuth:
        return _handleWaitForAuth(responderWithState, msgBytes, nonce);
    }
  }

  Phase _handleWaitForToken(
      ResponderWithState responderWithState, Uint8List msgBytes, Nonce nonce) {
    assert(input.authMethod.trustedResponderSharedKey == null);

    final responder = responderWithState.responder;
    final authToken = input.authMethod.authToken!;
    final msg = authToken.readEncryptedMessageOfType<Token>(
        msgBytes: msgBytes,
        nonce: nonce,
        msgType: MessageType.token,
        onDecryptionError: (msg) {
          dropResponder(responder, CloseCode.initiatorCouldNotDecrypt);
          return IgnoreMessageError(msg);
        });

    //TODO[trusted responder]: We currently do not keep the public key as we
    //      currently do not need it. But once we want to "trust" responder we
    //      need to keep it and need report it back to the client in some way.
    responder.setPermanentSharedKey(
        InitialClientAuthMethod.createResponderSharedPermanentKey(
            common.crypto, common.ourKeys, msg.key));

    responderWithState.state = State.waitForKeyMsg;

    return this;
  }

  Phase _handleWaitForKey(
      ResponderWithState responderWithState, Uint8List msgBytes, Nonce nonce) {
    final responder = responderWithState.responder;

    final sharedKey = responder.permanentSharedKey!;
    final msg = sharedKey.readEncryptedMessageOfType<Key>(
        msgBytes: msgBytes,
        nonce: nonce,
        msgType: MessageType.key,
        onDecryptionError: (msg) {
          dropResponder(responder, CloseCode.initiatorCouldNotDecrypt);
          return IgnoreMessageError(msg);
        });

    // generate session key, we only keep the shared key
    final sessionKey = common.crypto.createKeyStore();
    final sharedSessionKey = common.crypto.createSharedKeyStore(
        ownKeyStore: sessionKey, remotePublicKey: msg.key);
    responder.setSessionSharedKey(sharedSessionKey);

    sendMessage(Key(sessionKey.publicKey), to: responder);

    responderWithState.state = State.waitForAuth;
    return this;
  }

  Phase _handleWaitForAuth(
      ResponderWithState responderWithState, Uint8List msgBytes, Nonce nonce) {
    final responder = responderWithState.responder;

    final sharedKey = responder.sessionSharedKey!;
    final msg = sharedKey.readEncryptedMessageOfType<AuthResponder>(
      msgBytes: msgBytes,
      nonce: nonce,
      msgType: MessageType.auth,
    );

    if (msg.yourCookie != responder.cookiePair.ours) {
      throw ProtocolError('Bad repeated cookie in ${MessageType.auth} message');
    }

    final task = _selectTask(msg.tasks, forResponder: responder);
    logger.i('Selected task ${task.name}');

    /// AuthResponder parsing already validates integrity.
    final taskData = msg.data[task.name]!;
    task.initialize(taskData);
    logger.d('Initiated task ${task.name}');

    sendMessage(AuthInitiator(nonce.cookie, task.name, {task.name: task.data}),
        to: responder);

    // Make sure we don't drop the just paired responder.
    responders.remove(responder.id);

    // Drop all remaining responder.
    // (To list is needed or we modify the map while iterating over it.)
    for (final badResponder in responders.values.toList(growable: false)) {
      dropResponder(badResponder.responder, CloseCode.droppedByInitiator);
    }

    return TmpTaskPhaseImpl(common, responder.assertAuthenticated(), task);
  }

  /// Selects a task if possible, initiates connection termination if not.
  Task _selectTask(List<String> tasks, {required Responder forResponder}) {
    Task? task;
    for (final ourTask in input.tasks) {
      if (tasks.contains(ourTask.name)) {
        task = ourTask;
      }
    }

    if (task == null) {
      logger.w('No shared task for ${forResponder.id} found');
      sendMessage(Close(CloseCode.noSharedTask), to: forResponder);
      // We might diverge here in the future and instead "reset" to the
      // phase directly after the server handshake was done to allow a
      // updated client to connect shortly after. If we do so we probably
      // should also "trust" that client at this point so that no auth token
      // is used twice.
      //
      // FIXME we also need to signal to the client/application that no shared
      //       task was found while still closing the web-socket using goingAway.
      throw NoSharedTaskError();
    }

    return task;
  }

  void dropResponder(Responder responder, CloseCode closeCode) {
    responders.remove(responder.id);
    sendDropResponder(responder.id, closeCode);
  }
}

class TmpTaskPhaseImpl extends TaskPhase with InitiatorIdentity {
  TmpTaskPhaseImpl(
      CommonAfterServerHandshake common, Client pairedClient, Task task)
      : super(common, pairedClient, task);

  @override
  void handleServerMessage(Message msg) {
    throw UnimplementedError();
  }
}
