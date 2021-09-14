import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/src/crypto/crypto.dart'
    show InitialClientAuthMethod;
import 'package:dart_saltyrtc_client/src/logger.dart';
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
import 'package:dart_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;
import 'package:dart_saltyrtc_client/src/messages/reader.dart'
    show readEncryptedMessageOfType;
import 'package:dart_saltyrtc_client/src/messages/s2c/drop_responder.dart'
    show DropResponder;
import 'package:dart_saltyrtc_client/src/messages/s2c/new_responder.dart'
    show NewResponder;
import 'package:dart_saltyrtc_client/src/protocol/error.dart'
    show IgnoreMessageError, NoSharedTaskError, ProtocolError, ValidationError;
import 'package:dart_saltyrtc_client/src/protocol/peer.dart'
    show AuthenticatedResponder, Peer, Responder;
import 'package:dart_saltyrtc_client/src/protocol/phases/client_handshake.dart'
    show ClientHandshakePhase;
import 'package:dart_saltyrtc_client/src/protocol/phases/phase.dart'
    show
        InitiatorData,
        InitiatorSendDropResponder,
        Phase,
        CommonAfterServerHandshake,
        ClientHandshakeInput,
        InitiatorIdentity;
import 'package:dart_saltyrtc_client/src/protocol/task.dart' show Task;

class _ResponderWithState {
  final Responder responder;

  /// Used to identify the oldest responder during the path cleaning procedure.
  /// The client keeps a counter of how many responder connected.
  /// This is the value of that counter when this responder connected.
  final int counter;

  /// State of the handshake with a specific responder.
  ///
  /// If this is not set it meas we have not yet received any messages from the
  /// given responder and as such didn't yet setup the state.
  _State? state;

  _ResponderWithState(this.responder, {required this.counter});

  /// Returns the state for given responder, or creates it if necessary.
  ///
  /// Depending on the auth method the initial state is either `waitForTokenMsg`
  /// or `waitForKeyMsg`. In case of the later the responders permanent shared
  /// key is also set to the preset shared key.
  _State getOrCreateState(InitialClientAuthMethod authMethod) {
    final presetKey = authMethod.presetResponderSharedKey();
    if (presetKey == null) {
      return _State.waitForTokenMsg;
    } else {
      responder.setPermanentSharedKey(presetKey);
      return _State.waitForKeyMsg;
    }
  }
}

/// State of the handshake with a specific responder.
enum _State {
  waitForTokenMsg,
  waitForKeyMsg,
  waitForAuth,
}

class InitiatorClientHandshakePhase extends ClientHandshakePhase
    with InitiatorIdentity, InitiatorSendDropResponder {
  final InitiatorData data;
  final Map<IdResponder, _ResponderWithState> responders = {};

  /// Continuous incremental counter, used to track the oldest responder.
  ///
  /// Given of at least 2^53 (compiled to JS) id's this is more then enough
  /// for use to not worry about integer overflow.
  int responderCounter = 0;

  InitiatorClientHandshakePhase(
    CommonAfterServerHandshake common,
    ClientHandshakeInput input,
    this.data,
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
    responders[id] = _ResponderWithState(
      Responder(id, common.crypto),
      counter: responderCounter++,
    );

    // If we have more then this number of responders we drop the oldest.
    const responderSizeThreshold = 252;

    if (responders.length > responderSizeThreshold) {
      _dropOldestInactiveResponder();
    }
  }

  void _dropOldestInactiveResponder() {
    final responder = responders.entries
        .where((entry) => entry.value.state == null)
        .fold<_ResponderWithState?>(null, (min, entry) {
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
    final responderWithState = responders[nonce.source.asIdResponder()]!;
    final state = responderWithState.getOrCreateState(data.authMethod);

    switch (state) {
      case _State.waitForTokenMsg:
        return _handleWaitForToken(responderWithState, msgBytes, nonce);
      case _State.waitForKeyMsg:
        return _handleWaitForKey(responderWithState, msgBytes, nonce);
      case _State.waitForAuth:
        return _handleWaitForAuth(responderWithState, msgBytes, nonce);
    }
  }

  Phase _handleWaitForToken(
      _ResponderWithState responderWithState, Uint8List msgBytes, Nonce nonce) {
    assert(data.authMethod.presetResponderSharedKey() == null);

    final responder = responderWithState.responder;
    final msg = readEncryptedMessageOfType<Token>(
        sharedKey: data.authMethod.authToken()!,
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

    responderWithState.state = _State.waitForKeyMsg;

    return this;
  }

  Phase _handleWaitForKey(
      _ResponderWithState responderWithState, Uint8List msgBytes, Nonce nonce) {
    final responder = responderWithState.responder;

    final msg = readEncryptedMessageOfType<Key>(
        sharedKey: responder.permanentSharedKey!,
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

    responderWithState.state = _State.waitForAuth;
    return this;
  }

  Phase _handleWaitForAuth(
      _ResponderWithState responderWithState, Uint8List msgBytes, Nonce nonce) {
    final responder = responderWithState.responder;

    final msg = readEncryptedMessageOfType<AuthResponder>(
      sharedKey: responder.sessionSharedKey!,
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

    return _createTaskPhase(
      common: common,
      pairedWith: responder.assertAuthenticated(),
      task: task,
    );
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

  static Phase _createTaskPhase({
    required CommonAfterServerHandshake common,
    required AuthenticatedResponder pairedWith,
    required Task task,
    //maybe bool wasTrusted
  }) {
    throw UnimplementedError();
  }

  void dropResponder(Responder responder, CloseCode closeCode) {
    responders.remove(responder.id);
    logger.d('Dropping responder ${responder.id}');
    sendMessage(DropResponder(responder.id, closeCode), to: common.server);
  }
}
