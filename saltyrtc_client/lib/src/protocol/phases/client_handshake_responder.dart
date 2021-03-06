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
import 'package:xayn_saltyrtc_client/src/crypto/crypto.dart' show KeyStore;
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
import 'package:xayn_saltyrtc_client/src/messages/id.dart' show Id;
import 'package:xayn_saltyrtc_client/src/messages/message.dart'
    show MessageType;
import 'package:xayn_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;
import 'package:xayn_saltyrtc_client/src/messages/reader.dart'
    show MessageDecryptionExt;
import 'package:xayn_saltyrtc_client/src/messages/s2c/disconnected.dart'
    show Disconnected;
import 'package:xayn_saltyrtc_client/src/messages/s2c/new_initiator.dart'
    show NewInitiator;
import 'package:xayn_saltyrtc_client/src/messages/validation.dart'
    show validateInitiatorId;
import 'package:xayn_saltyrtc_client/src/protocol/error.dart'
    show ProtocolErrorException;
import 'package:xayn_saltyrtc_client/src/protocol/peer.dart' show Initiator;
import 'package:xayn_saltyrtc_client/src/protocol/phases/client_handshake.dart'
    show ClientHandshakePhase;
import 'package:xayn_saltyrtc_client/src/protocol/phases/phase.dart'
    show
        AfterServerHandshakeCommon,
        Phase,
        ResponderConfig,
        ResponderIdentity,
        WithPeer;
import 'package:xayn_saltyrtc_client/src/protocol/phases/task.dart'
    show ResponderTaskPhase;
import 'package:xayn_saltyrtc_client/src/protocol/task.dart' show TaskBuilder;

/// State of the handshake with the initiator.
enum State {
  waitForKeyMsg,
  waitForAuth,
}

class InitiatorWithState {
  final Initiator initiator;
  State state;
  final KeyStore sessionKey;

  InitiatorWithState({
    required this.initiator,
    required this.state,
    required this.sessionKey,
  });
}

class ResponderClientHandshakePhase extends ClientHandshakePhase
    with ResponderIdentity, WithPeer {
  @override
  ResponderConfig config;

  @override
  Initiator? get pairedClient => initiatorWithState?.initiator;
  InitiatorWithState? initiatorWithState;

  ResponderClientHandshakePhase(
    AfterServerHandshakeCommon common,
    this.config, {
    required bool initiatorConnected,
  }) : super(common) {
    if (initiatorConnected) {
      startNewHandshake();
    } else {
      logger.d('waiting for initiator to connect');
    }
  }

  void startNewHandshake() {
    logger.d('starting new c2c handshake for responder ${common.address}');
    final initiator = Initiator(common.crypto);
    if (config.authToken != null) {
      sendMessage(
        Token(config.permanentKey.publicKey),
        to: initiator,
        authToken: config.authToken,
      );
    }
    initiator.setPermanentSharedKey(
      common.crypto.createSharedKeyStore(
        ownKeyStore: config.permanentKey,
        remotePublicKey: config.initiatorPermanentPublicKey,
      ),
    );
    final sessionKey = common.crypto.createKeyStore();
    sendMessage(Key(sessionKey.publicKey), to: initiator);

    initiatorWithState = InitiatorWithState(
      initiator: initiator,
      state: State.waitForKeyMsg,
      sessionKey: sessionKey,
    );
  }

  @override
  Phase onProtocolError(ProtocolErrorException e, Id? source) {
    if (source != null && source.isInitiator()) {
      emitEvent(events.ProtocolErrorWithPeer(events.PeerKind.unauthenticated));
      initiatorWithState = null;
      // We can't just reset the initiator state as we can't tell the initiator
      // that we did so. To again communicate with the initiator we need a new
      // address, so we need to close the connection. As the protocol error was
      // not with the server we close the connection with `goingAway`.
      close(CloseCode.goingAway, 'c2c protocol error');
      return this;
    } else {
      return super.onProtocolError(e, source);
    }
  }

  @override
  Phase handleDisconnected(Disconnected msg) {
    final id = msg.id;
    validateInitiatorId(id.value);
    initiatorWithState = null;
    emitEvent(events.PeerDisconnected(events.PeerKind.unauthenticated));
    return this;
  }

  @override
  Phase handleSendErrorByDestination(Id destination) {
    initiatorWithState = null;
    emitEvent(
      events.SendingMessageToPeerFailed(events.PeerKind.unauthenticated),
    );
    return this;
  }

  @override
  Phase handleNewInitiator(NewInitiator msg) {
    startNewHandshake();
    return this;
  }

  @override
  Phase handleClientMessage(Uint8List msgBytes, Nonce nonce) {
    // We only handle message from clients if the initiator is set
    // so it should never be unset.
    final initiatorWithState = this.initiatorWithState!;
    switch (initiatorWithState.state) {
      case State.waitForKeyMsg:
        return _handleWaitForKeyMsg(msgBytes, nonce);
      case State.waitForAuth:
        return _handleWaitForAuthMsg(msgBytes, nonce);
    }
  }

  Phase _handleWaitForKeyMsg(Uint8List msgBytes, Nonce nonce) {
    final initiatorWithState = this.initiatorWithState!;
    final initiator = initiatorWithState.initiator;

    final keyMsg =
        initiator.permanentSharedKey!.readEncryptedMessageOfType<Key>(
      msgBytes: msgBytes,
      nonce: nonce,
      msgType: MessageType.key,
    );

    initiator.setSessionSharedKey(
      common.crypto.createSharedKeyStore(
        ownKeyStore: initiatorWithState.sessionKey,
        remotePublicKey: keyMsg.key,
      ),
    );

    final taskData = {
      for (final task in config.tasks) task.name: task.getInitialResponderData()
    };
    final taskNames = [for (final task in config.tasks) task.name];

    sendMessage(
      AuthResponder(initiator.cookiePair.theirs!, taskNames, taskData),
      to: initiator,
    );

    initiatorWithState.state = State.waitForAuth;
    return this;
  }

  Phase _handleWaitForAuthMsg(Uint8List msgBytes, Nonce nonce) {
    final initiatorWithState = this.initiatorWithState!;
    final initiator = initiatorWithState.initiator;

    final msg = initiator.sessionSharedKey!.readEncryptedMessage(
      msgBytes: msgBytes,
      nonce: nonce,
    );

    if (msg is Close) {
      // We expect a potential Close message, but only with a
      // CloseCode.noSharedTask reason.
      if (msg.reason == CloseCode.noSharedTask) {
        logger.w('No shared task for ${initiator.id} found');
        emitEvent(events.NoSharedTaskFound());
        close(CloseCode.goingAway, 'no shared task was found');
        return this;
      }
    }
    if (msg is! AuthInitiator) {
      throw ProtocolErrorException(
        'Unexpected message of type ${msg.type}, expected auth',
      );
    }

    if (msg.yourCookie != initiator.cookiePair.ours) {
      throw const ProtocolErrorException(
        'Bad your_cookie in ${MessageType.auth} message',
      );
    }

    final taskName = msg.task;
    final TaskBuilder taskBuilder;
    try {
      taskBuilder = config.tasks.firstWhere((task) => task.name == taskName);
    } on StateError {
      throw ProtocolErrorException('unknown selected task ${msg.task}');
    }

    final task = taskBuilder.buildResponderTask(msg.data[taskName]);

    emitEvent(events.ResponderAuthenticated(config.permanentKey.publicKey));

    return ResponderTaskPhase(
      common,
      config,
      initiator.assertAuthenticated(),
      task,
    );
  }
}
