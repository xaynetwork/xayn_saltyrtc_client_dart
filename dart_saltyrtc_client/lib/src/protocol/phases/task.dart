import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/src/logger.dart' show logger;
import 'package:dart_saltyrtc_client/src/messages/c2c/application.dart'
    show Application;
import 'package:dart_saltyrtc_client/src/messages/c2c/close.dart' show Close;
import 'package:dart_saltyrtc_client/src/messages/c2c/task_message.dart'
    show TaskMessage;
import 'package:dart_saltyrtc_client/src/messages/close_code.dart'
    show CloseCode;
import 'package:dart_saltyrtc_client/src/messages/id.dart' show Id;
import 'package:dart_saltyrtc_client/src/messages/message.dart' show Message;
import 'package:dart_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;
import 'package:dart_saltyrtc_client/src/messages/reader.dart'
    show MessageDecryptionExt;
import 'package:dart_saltyrtc_client/src/messages/s2c/disconnected.dart'
    show Disconnected;
import 'package:dart_saltyrtc_client/src/messages/s2c/new_initiator.dart'
    show NewInitiator;
import 'package:dart_saltyrtc_client/src/messages/s2c/new_responder.dart'
    show NewResponder;
import 'package:dart_saltyrtc_client/src/messages/s2c/send_error.dart'
    show SendError;
import 'package:dart_saltyrtc_client/src/messages/validation.dart'
    show validateIdResponder, validateIdInitiator;
import 'package:dart_saltyrtc_client/src/protocol/error.dart'
    show ProtocolException;
import 'package:dart_saltyrtc_client/src/protocol/events.dart' as events;
import 'package:dart_saltyrtc_client/src/protocol/peer.dart'
    show AuthenticatedInitiator, AuthenticatedResponder, Client, Peer;
import 'package:dart_saltyrtc_client/src/protocol/phases/client_handshake_initiator.dart'
    show InitiatorClientHandshakePhase;
import 'package:dart_saltyrtc_client/src/protocol/phases/client_handshake_responder.dart'
    show ResponderClientHandshakePhase;
import 'package:dart_saltyrtc_client/src/protocol/phases/phase.dart'
    show
        AfterServerHandshakePhase,
        AfterServerHandshakeCommon,
        InitiatorConfig,
        InitiatorIdentity,
        InitiatorSendDropResponder,
        Phase,
        ResponderConfig,
        ResponderIdentity,
        WithPeer;
import 'package:dart_saltyrtc_client/src/protocol/task.dart' show Task;
import 'package:meta/meta.dart' show protected;

abstract class TaskPhase extends AfterServerHandshakePhase with WithPeer {
  @override
  Client get pairedClient;

  final Task task;

  TaskPhase(AfterServerHandshakeCommon common, this.task) : super(common);

  @protected
  Phase handleServerMessage(Message msg);

  @override
  Phase onProtocolError(ProtocolException e, Id? source) {
    if (source == pairedClient.id) {
      sendMessage(Close(e.closeCode), to: pairedClient);
      close(CloseCode.closingNormal, 'closing after c2c protocol error');
      return this;
    } else {
      return super.onProtocolError(e, source);
    }
  }

  @override
  Phase run(Peer source, Uint8List msgBytes, Nonce nonce) {
    final msg = source.sessionSharedKey!
        .readEncryptedMessage(msgBytes: msgBytes, nonce: nonce);

    if (nonce.source.isServer()) {
      if (msg is SendError) {
        return handleSendError(msg);
      } else if (msg is Disconnected) {
        return handleDisconnected(msg);
      } else {
        return handleServerMessage(msg);
      }
    } else {
      return handlePeerMessage(msg);
    }
  }

  @protected
  Phase handlePeerMessage(Message msg) {
    if (msg is TaskMessage) {
      logger.d('Received task message');
      return handleTaskMessage(msg);
    } else if (msg is Close) {
      logger.d('Received close message');
      return handleClose(msg);
    } else if (msg is Application) {
      return handleApplicationMessage(msg);
    } else {
      throw ProtocolException(
        'Invalid message during task phase. Message type: ${msg.type}',
      );
    }
  }

  @protected
  Phase handleClose(Close msg) {
    throw UnimplementedError();
  }

  @protected
  Phase handleTaskMessage(TaskMessage msg) {
    throw UnimplementedError();
  }

  @protected
  Phase handleApplicationMessage(Application msg) {
    throw UnimplementedError();
  }
}

class InitiatorTaskPhase extends TaskPhase
    with InitiatorSendDropResponder, InitiatorIdentity {
  @override
  final InitiatorConfig config;
  @override
  final AuthenticatedResponder pairedClient;

  InitiatorTaskPhase(
    AfterServerHandshakeCommon common,
    this.config,
    this.pairedClient,
    Task task,
  ) : super(common, task);

  @override
  Phase handleDisconnected(Disconnected msg) {
    final id = msg.id;
    validateIdResponder(id.value);
    if (id != pairedClient.id) {
      emitEvent(events.PeerDisconnected(events.PeerKind.unknownPeer));
      return this;
    } else {
      emitEvent(events.PeerDisconnected(events.PeerKind.authenticatedPeer));
      return InitiatorClientHandshakePhase(common, config);
    }
  }

  @override
  Phase handleSendErrorByDestination(Id destination) {
    if (destination != pairedClient.id) {
      emitEvent(events.SendingMessageToPeerFailed(wasAuthenticated: false));
      return this;
    } else {
      emitEvent(events.SendingMessageToPeerFailed(wasAuthenticated: true));
      return InitiatorClientHandshakePhase(common, config);
    }
  }

  @override
  Phase handleServerMessage(Message msg) {
    if (msg is NewResponder) {
      logger.d('Dropping new responder while in task phase');
      sendDropResponder(msg.id, CloseCode.droppedByInitiator);
    } else {
      logger.w('Unexpected server message type: ${msg.type}');
    }
    return this;
  }
}

class ResponderTaskPhase extends TaskPhase with ResponderIdentity {
  @override
  final ResponderConfig config;
  @override
  final AuthenticatedInitiator pairedClient;

  ResponderTaskPhase(
    AfterServerHandshakeCommon common,
    this.config,
    this.pairedClient,
    Task task,
  ) : super(common, task);

  @override
  Phase handleDisconnected(Disconnected msg) {
    final id = msg.id;
    validateIdInitiator(id.value);
    emitEvent(events.PeerDisconnected(events.PeerKind.authenticatedPeer));
    return ResponderClientHandshakePhase(common, config,
        initiatorConnected: false);
  }

  @override
  Phase handleSendErrorByDestination(Id destination) {
    emitEvent(events.SendingMessageToPeerFailed(wasAuthenticated: true));
    return ResponderClientHandshakePhase(common, config,
        initiatorConnected: false);
  }

  @override
  Phase handleServerMessage(Message msg) {
    if (msg is NewInitiator) {
      // if a new initiator connected the current session is not valid anymore
      logger.d('A new initiator connected');
      // we could also go back to `ResponderClientHandshakePhase`, but we also need to notify the Task
      close(CloseCode.closingNormal, 'Another initiator connected');
      return this;
    } else {
      logger.w('Unexpected server message type: ${msg.type}');
      return this;
    }
  }
}
