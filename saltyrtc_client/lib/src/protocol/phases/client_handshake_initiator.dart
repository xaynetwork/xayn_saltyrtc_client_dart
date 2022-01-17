// Copyright 2021 Xayn AG
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:typed_data' show Uint8List;

import 'package:xayn_saltyrtc_client/events.dart' as events;
import 'package:xayn_saltyrtc_client/src/crypto/crypto.dart'
    show InitialClientAuthMethod;
import 'package:xayn_saltyrtc_client/src/logger.dart' show logger;
import 'package:xayn_saltyrtc_client/src/messages/c2c/auth_initiator.dart'
    show AuthInitiator;
import 'package:xayn_saltyrtc_client/src/messages/c2c/auth_responder.dart'
    show AuthResponder;
import 'package:xayn_saltyrtc_client/src/messages/c2c/close.dart' show Close;
import 'package:xayn_saltyrtc_client/src/messages/c2c/key.dart' show Key;
import 'package:xayn_saltyrtc_client/src/messages/c2c/token.dart' show Token;
import 'package:xayn_saltyrtc_client/src/messages/close_code.dart'
    show CloseCode;
import 'package:xayn_saltyrtc_client/src/messages/id.dart' show Id, ResponderId;
import 'package:xayn_saltyrtc_client/src/messages/message.dart'
    show MessageType;
import 'package:xayn_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;
import 'package:xayn_saltyrtc_client/src/messages/reader.dart'
    show MessageDecryptionExt;
import 'package:xayn_saltyrtc_client/src/messages/s2c/disconnected.dart'
    show Disconnected;
import 'package:xayn_saltyrtc_client/src/messages/s2c/new_responder.dart'
    show NewResponder;
import 'package:xayn_saltyrtc_client/src/messages/validation.dart'
    show validateResponderId;
import 'package:xayn_saltyrtc_client/src/protocol/error.dart'
    show ProtocolErrorException;
import 'package:xayn_saltyrtc_client/src/protocol/peer.dart'
    show Peer, Responder;
import 'package:xayn_saltyrtc_client/src/protocol/phases/client_handshake.dart'
    show ClientHandshakePhase;
import 'package:xayn_saltyrtc_client/src/protocol/phases/phase.dart'
    show
        AfterServerHandshakeCommon,
        InitiatorConfig,
        InitiatorIdentity,
        InitiatorSendDropResponder,
        Phase;
import 'package:xayn_saltyrtc_client/src/protocol/phases/task.dart'
    show InitiatorTaskPhase;
import 'package:xayn_saltyrtc_client/src/protocol/task.dart' show TaskBuilder;

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
  final Map<ResponderId, ResponderWithState> responders = {};

  @override
  final InitiatorConfig config;

  /// Continuous incremental counter, used to track the oldest responder.
  ///
  /// Given of at least 2^53 (compiled to JS) id's this is more then enough
  /// for use to not worry about integer overflow.
  int responderCounter = 0;

  InitiatorClientHandshakePhase(
    AfterServerHandshakeCommon common,
    this.config,
  ) : super(common);

  bool thereIsAOngoingHandshake() {
    return responders.values.any((responder) => responder.receivedAnyMessage);
  }

  @override
  Peer? getPeerWithId(Id id) {
    if (id.isServer()) return common.server;
    if (id.isResponder()) {
      return responders[id]?.responder;
    }
    return null;
  }

  @override
  Phase onProtocolError(ProtocolErrorException e, Id? source) {
    if (source != null && source.isResponder()) {
      final wasKnown = dropResponder(source.asResponder(), e.closeCode);
      if (e.closeCode == CloseCode.initiatorCouldNotDecrypt) {
        emitEvent(events.InitiatorCouldNotDecrypt());
      } else {
        final event =
            events.ProtocolErrorWithPeer(events.PeerKind.unauthenticated);
        if (wasKnown || !thereIsAOngoingHandshake()) {
          emitEvent(event);
        } else {
          emitEvent(events.AdditionalResponderEvent(event));
        }
      }
      return this;
    } else {
      return super.onProtocolError(e, source);
    }
  }

  @override
  Phase handleDisconnected(Disconnected msg) {
    final id = msg.id;
    validateResponderId(id.value);
    final removed = responders.remove(id);
    final event = events.PeerDisconnected(events.PeerKind.unauthenticated);
    if ((removed?.receivedAnyMessage ?? false) || !thereIsAOngoingHandshake()) {
      emitEvent(event);
    } else {
      emitEvent(events.AdditionalResponderEvent(event));
    }
    return this;
  }

  @override
  Phase handleSendErrorByDestination(Id destination) {
    final removed = responders.remove(destination);
    if (removed != null) {
      emitEvent(
        events.SendingMessageToPeerFailed(events.PeerKind.unauthenticated),
      );
    } else {
      logger.d('send-error from already removed destination');
    }
    return this;
  }

  @override
  Phase handleNewResponder(NewResponder msg) {
    addNewResponder(msg.id);
    return this;
  }

  /// Adds a new responder the the container of known responders.
  void addNewResponder(ResponderId id) {
    // This will automatically override any previously set state.
    responders[id] = ResponderWithState(
      Responder(id, common.crypto),
      counter: responderCounter++,
      authMethod: config.authMethod,
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
      dropResponder(responder.responder.id, CloseCode.droppedByInitiator);
    } else {
      // Can not be reached as at least the "just added" responder
      // can always be dropped.
      logger.e("can't clean path");
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
    ResponderWithState responderWithState,
    Uint8List msgBytes,
    Nonce nonce,
  ) {
    assert(config.authMethod.trustedResponderSharedKey == null);

    final responder = responderWithState.responder;
    final authToken = config.authMethod.authToken!;
    final msg = authToken.readEncryptedMessageOfType<Token>(
      msgBytes: msgBytes,
      nonce: nonce,
      msgType: MessageType.token,
      decryptionErrorCloseCode: CloseCode.initiatorCouldNotDecrypt,
    );

    responder.setPermanentSharedKey(
      InitialClientAuthMethod.createResponderSharedPermanentKey(
        common.crypto,
        config.permanentKey,
        msg.key,
      ),
    );

    responderWithState.state = State.waitForKeyMsg;

    return this;
  }

  Phase _handleWaitForKey(
    ResponderWithState responderWithState,
    Uint8List msgBytes,
    Nonce nonce,
  ) {
    final responder = responderWithState.responder;

    final sharedKey = responder.permanentSharedKey!;
    final msg = sharedKey.readEncryptedMessageOfType<Key>(
      msgBytes: msgBytes,
      nonce: nonce,
      msgType: MessageType.key,
      decryptionErrorCloseCode: CloseCode.initiatorCouldNotDecrypt,
    );

    // generate session key, we only keep the shared key
    final sessionKey = common.crypto.createKeyStore();
    final sharedSessionKey = common.crypto.createSharedKeyStore(
      ownKeyStore: sessionKey,
      remotePublicKey: msg.key,
    );
    responder.setSessionSharedKey(sharedSessionKey);

    sendMessage(Key(sessionKey.publicKey), to: responder);

    responderWithState.state = State.waitForAuth;
    return this;
  }

  Phase _handleWaitForAuth(
    ResponderWithState responderWithState,
    Uint8List msgBytes,
    Nonce nonce,
  ) {
    final responder = responderWithState.responder;

    final sharedKey = responder.sessionSharedKey!;
    final msg = sharedKey.readEncryptedMessageOfType<AuthResponder>(
      msgBytes: msgBytes,
      nonce: nonce,
      msgType: MessageType.auth,
    );

    if (msg.yourCookie != responder.cookiePair.ours) {
      throw const ProtocolErrorException(
        'Bad your_cookie in ${MessageType.auth} message',
      );
    }

    final taskBuilder = _selectTaskBuilder(msg.tasks, responder);
    if (taskBuilder == null) {
      logger.w('No shared task for ${responder.id} found');
      sendMessage(Close(CloseCode.noSharedTask), to: responder);
      emitEvent(events.NoSharedTaskFound());
      close(CloseCode.goingAway, 'no shared task was found');
      return this;
    }
    logger.i('Selected task ${taskBuilder.name}');

    /// AuthResponder parsing already validates integrity.
    final taskData = msg.data[taskBuilder.name];
    final taskAndData = taskBuilder.buildInitiatorTask(taskData);
    logger.d('Initiated task ${taskBuilder.name}');

    sendMessage(
      AuthInitiator(
        nonce.cookie,
        taskBuilder.name,
        {taskBuilder.name: taskAndData.second},
      ),
      to: responder,
    );

    // Make sure we don't drop the just paired responder.
    responders.remove(responder.id);

    // Drop all remaining responder.
    // (toList is needed because we modify the map while iterating over it)
    for (final badResponder in responders.values.toList(growable: false)) {
      dropResponder(badResponder.responder.id, CloseCode.droppedByInitiator);
    }

    emitEvent(
      events.ResponderAuthenticated(
        responder.permanentSharedKey!.remotePublicKey,
      ),
    );

    return InitiatorTaskPhase(
      common,
      config,
      responder.assertAuthenticated(),
      taskAndData.first,
    );
  }

  /// Selects a task if possible, initiates connection termination if not.
  TaskBuilder? _selectTaskBuilder(List<String> tasks, Responder forResponder) {
    TaskBuilder? task;
    for (final ourTask in config.tasks) {
      if (tasks.contains(ourTask.name)) {
        task = ourTask;
      }
    }

    return task;
  }

  bool dropResponder(ResponderId responder, CloseCode closeCode) {
    final known = responders.remove(responder)?.receivedAnyMessage ?? false;
    sendDropResponder(responder, closeCode);
    return known;
  }
}
