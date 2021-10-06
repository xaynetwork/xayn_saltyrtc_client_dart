import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/src/crypto/crypto.dart' show KeyStore;
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
import 'package:dart_saltyrtc_client/src/messages/id.dart' show Id;
import 'package:dart_saltyrtc_client/src/messages/message.dart'
    show MessageType;
import 'package:dart_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;
import 'package:dart_saltyrtc_client/src/messages/reader.dart'
    show MessageDecryptionExt;
import 'package:dart_saltyrtc_client/src/messages/s2c/disconnected.dart'
    show Disconnected;
import 'package:dart_saltyrtc_client/src/messages/s2c/new_initiator.dart'
    show NewInitiator;
import 'package:dart_saltyrtc_client/src/messages/validation.dart'
    show validateIdInitiator;
import 'package:dart_saltyrtc_client/src/protocol/error.dart'
    show ProtocolException;
import 'package:dart_saltyrtc_client/src/protocol/events.dart' as events;
import 'package:dart_saltyrtc_client/src/protocol/peer.dart' show Initiator;
import 'package:dart_saltyrtc_client/src/protocol/phases/client_handshake.dart'
    show ClientHandshakePhase;
import 'package:dart_saltyrtc_client/src/protocol/phases/phase.dart'
    show
        AfterServerHandshakeCommon,
        Phase,
        ResponderConfig,
        ResponderIdentity,
        WithPeer;
import 'package:dart_saltyrtc_client/src/protocol/phases/task.dart'
    show ResponderTaskPhase;
import 'package:dart_saltyrtc_client/src/protocol/task.dart' show TaskBuilder;

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
    }
  }

  void startNewHandshake() {
    final initiator = Initiator(common.crypto);
    if (config.authToken != null) {
      sendMessage(Token(config.permanentKey.publicKey),
          to: initiator, authToken: config.authToken);
    }
    initiator.setPermanentSharedKey(common.crypto.createSharedKeyStore(
        ownKeyStore: config.permanentKey,
        remotePublicKey: config.initiatorPermanentPublicKey));
    final sessionKey = common.crypto.createKeyStore();
    sendMessage(Key(sessionKey.publicKey), to: initiator);

    initiatorWithState = InitiatorWithState(
      initiator: initiator,
      state: State.waitForKeyMsg,
      sessionKey: sessionKey,
    );
  }

  @override
  Phase handleDisconnected(Disconnected msg) {
    final id = msg.id;
    validateIdInitiator(id.value);
    initiatorWithState = null;
    emitEvent(
        events.PeerDisconnected(events.PeerKind.unauthenticatedTargetPeer));
    return this;
  }

  @override
  Phase handleSendErrorByDestination(Id destination) {
    initiatorWithState = null;
    emitEvent(events.SendingMessageToPeerFailed(wasAuthenticated: false));
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

    initiator.setSessionSharedKey(common.crypto.createSharedKeyStore(
      ownKeyStore: initiatorWithState.sessionKey,
      remotePublicKey: keyMsg.key,
    ));

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
        // no close code is used in this case
        close(null, 'no shared task was found');
        return this;
      }
    }
    if (msg is! AuthInitiator) {
      throw ProtocolException(
          'Unexpected message of type ${msg.type}, expected auth');
    }

    if (msg.yourCookie != initiator.cookiePair.ours) {
      throw ProtocolException('Bad your_cookie in ${MessageType.auth} message');
    }

    final taskName = msg.task;
    final TaskBuilder taskBuilder;
    try {
      taskBuilder = config.tasks.firstWhere((task) => task.name == taskName);
    } on StateError {
      throw ProtocolException('unknown selected task ${msg.task}');
    }

    final task = taskBuilder.buildResponderTask(msg.data[taskName]);

    emitEvent(events.ResponderAuthenticated(config.permanentKey.publicKey));

    return ResponderTaskPhase(
        common, config, initiator.assertAuthenticated(), task);
  }
}
