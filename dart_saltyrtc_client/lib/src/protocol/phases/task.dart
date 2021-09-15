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
import 'package:dart_saltyrtc_client/src/messages/message.dart'
    show TaskData, Message;
import 'package:dart_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;
import 'package:dart_saltyrtc_client/src/messages/reader.dart' show readMessage;
import 'package:dart_saltyrtc_client/src/messages/s2c/disconnected.dart'
    show Disconnected;
import 'package:dart_saltyrtc_client/src/messages/s2c/new_initiator.dart'
    show NewInitiator;
import 'package:dart_saltyrtc_client/src/messages/s2c/new_responder.dart'
    show NewResponder;
import 'package:dart_saltyrtc_client/src/messages/s2c/send_error.dart'
    show SendError;
import 'package:dart_saltyrtc_client/src/messages/validation.dart'
    show ValidationError;
import 'package:dart_saltyrtc_client/src/protocol/error.dart'
    show ProtocolError, ensureNotNull, SaltyRtcError;
import 'package:dart_saltyrtc_client/src/protocol/peer.dart'
    show Client, Responder, Initiator, Peer;
import 'package:dart_saltyrtc_client/src/protocol/phases/phase.dart'
    show
        Phase,
        CommonAfterServerHandshake,
        AfterServerHandshakePhase,
        InitiatorSendDropResponder;
import 'package:dart_saltyrtc_client/src/protocol/role.dart' show Role;
import 'package:dart_saltyrtc_client/src/protocol/task.dart' show Task;
import 'package:meta/meta.dart' show protected;

abstract class TaskPhase extends AfterServerHandshakePhase {
  final Client pairedClient;

  final Task task;
  final TaskData taskData;

  TaskPhase(CommonAfterServerHandshake common, this.pairedClient, this.task,
      this.taskData)
      : super(common);

  @protected
  void handleServerMessage(Message msg);

  @override
  Phase run(Uint8List msgBytes, Nonce nonce) {
    final sks = ensureNotNull(getPeerWithId(nonce.source).sessionSharedKey);
    final decryptedBytes =
        sks.decrypt(ciphertext: msgBytes, nonce: nonce.toBytes());

    final msg = readMessage(decryptedBytes, taskTypes: task.supportedTypes);
    if (nonce.source.isServer()) {
      if (msg is SendError) {
        handleSendError(msg);
      } else if (msg is Disconnected) {
        handleDisconnected(msg);
      } else {
        handleServerMessage(msg);
      }
    } else {
      handlePeerMessage(msg);
    }

    // the phase does not change anymore
    return this;
  }

  @override
  Peer getPeerWithId(Id id) {
    if (id.isServer()) {
      return common.server;
    } else if (id == pairedClient.id) {
      return pairedClient;
    } else if (role == Role.initiator && id.isResponder()) {
      // see getPeerWithId of InitiatorPhase
      throw ValidationError(
        'Invalid responder id: $id',
        isProtocolError: false,
      );
    }
    throw ProtocolError('Invalid responder id: $id');
  }

  @protected
  void handlePeerMessage(Message msg) {
    if (msg is TaskMessage) {
      logger.d('Received task message');
      handleTaskMessage(msg);
    } else if (msg is Close) {
      logger.d('Received close message');
      handleClose(msg);
    } else if (msg is Application) {
      handleApplicationMessage(msg);
    } else {
      throw ProtocolError(
        'Invalid message during task phase. Message type: ${msg.type}',
      );
    }
  }

  @protected
  void handleClose(Close msg) {
    throw UnimplementedError();
  }

  @protected
  void handleTaskMessage(TaskMessage msg) {
    throw UnimplementedError();
  }

  @protected
  void handleApplicationMessage(Application msg) {
    throw UnimplementedError();
  }
}

class InitiatorTaskPhase extends TaskPhase with InitiatorSendDropResponder {
  @override
  final Responder pairedClient;

  @override
  Role get role => Role.initiator;

  InitiatorTaskPhase(
    CommonAfterServerHandshake common,
    this.pairedClient,
    Task task,
    TaskData taskData,
  ) : super(common, pairedClient, task, taskData);

  @override
  void handleServerMessage(Message msg) {
    if (msg is NewResponder) {
      logger.d('Dropping new responder while in task phase');
      sendDropResponder(msg.id, CloseCode.droppedByInitiator);
    } else {
      logger.w('Unexpected server message type: ${msg.type}');
    }
  }
}

class ResponderTaskPhase extends TaskPhase {
  @override
  final Initiator pairedClient;

  @override
  Role get role => Role.responder;

  ResponderTaskPhase(
    CommonAfterServerHandshake common,
    this.pairedClient,
    Task task,
    TaskData taskData,
  ) : super(common, pairedClient, task, taskData);

  @override
  void handleServerMessage(Message msg) {
    if (msg is NewInitiator) {
      // if a new initiator connected the current session is not valid anymore
      logger.d('A new initiator connected');
      // we could also go back to `ResponderClientHandshakePhase`, but we also need to notify the Task
      throw SaltyRtcError(
        CloseCode.closingNormal,
        'Another initiator connected',
      );
    } else {
      logger.w('Unexpected server message type: ${msg.type}');
    }
  }
}