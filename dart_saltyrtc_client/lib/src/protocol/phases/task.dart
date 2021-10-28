import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/src/logger.dart' show logger;
import 'package:dart_saltyrtc_client/src/messages/c2c/application.dart'
    show Application;
import 'package:dart_saltyrtc_client/src/messages/c2c/close.dart' show Close;
import 'package:dart_saltyrtc_client/src/messages/c2c/task_message.dart'
    show TaskMessage;
import 'package:dart_saltyrtc_client/src/messages/close_code.dart'
    show CloseCode;
import 'package:dart_saltyrtc_client/src/messages/id.dart' show Id, ResponderId;
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
    show validateResponderId, validateInitiatorId;
import 'package:dart_saltyrtc_client/src/protocol/error.dart'
    show ProtocolErrorException;
import 'package:dart_saltyrtc_client/src/protocol/events.dart' as events;
import 'package:dart_saltyrtc_client/src/protocol/events.dart' show Event;
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
import 'package:dart_saltyrtc_client/src/protocol/task.dart'
    show SaltyRtcTaskLink, Task, CancelReason;
import 'package:dart_saltyrtc_client/src/utils.dart' show EmitEventExt;
import 'package:meta/meta.dart' show protected;

class _Link extends SaltyRtcTaskLink {
  TaskPhase? _phase;

  _Link(TaskPhase this._phase);

  @override
  void close(CloseCode closeCode, [String? reason]) {
    final phase = _phase;
    if (phase != null) {
      phase.close(closeCode, reason ?? 'closed by task');
    }
  }

  @override
  void emitEvent(Event event) {
    final phase = _phase;
    if (phase != null) {
      // by-pass `TaskPhase.emitEvent` to prevent event re-receiving
      phase.common.events.emitEvent(event);
    }
  }

  @override
  void sendMessage(TaskMessage msg) {
    final phase = _phase;
    if (phase != null) {
      phase.sendMessage(msg, to: phase.pairedClient);
    }
  }

  @override
  void requestHandover() {
    final phase = _phase;
    if (phase != null) {
      phase.close(CloseCode.handover, 'handover');
    } else {
      throw StateError('already disconnected from phase');
    }
  }

  /// Disconnects task from the client.
  ///
  /// This means the task can no longer access the client (but the client
  /// can still access the task).
  void disconnect() {
    _phase = null;
  }
}

abstract class TaskPhase extends AfterServerHandshakePhase with WithPeer {
  @override
  Client get pairedClient;

  final Task task;
  late _Link _link;

  TaskPhase(AfterServerHandshakeCommon common, this.task) : super(common) {
    _link = _Link(this);
    taskCallGuard(() {
      task.start(_link);
    });
  }

  void taskCallGuard(void Function() func) {
    try {
      func();
    } catch (e, s) {
      killBecauseOf(e, s);
    }
  }

  @override
  void tellTaskThatHandoverCompleted() {
    taskCallGuard(() {
      task.handleHandover(common.events);
    });
    _link.disconnect();
  }

  @override
  void cancelTask({bool serverDisconnected = false}) {
    _cancelTask(serverDisconnected
        ? CancelReason.serverDisconnected
        : CancelReason.closing);
  }

  @override
  bool sendCloseMsgToClientIfNecessary(CloseCode closeCode) {
    sendMessage(Close(closeCode), to: pairedClient);
    return true;
  }

  @override
  void emitEvent(Event event, [StackTrace? st]) {
    common.events.emitEvent(event, st);
    taskCallGuard(() {
      task.handleEvent(event);
    });
  }

  @protected
  Phase handleServerMessage(Message msg);

  @override
  Phase onProtocolError(ProtocolErrorException e, Id? source) {
    if (source == pairedClient.id) {
      close(e.closeCode, 'closing after c2c protocol error');
      emitEvent(events.ProtocolErrorWithPeer(events.PeerKind.authenticated));
      return this;
    } else {
      return super.onProtocolError(e, source);
    }
  }

  @override
  Phase run(Peer source, Uint8List msgBytes, Nonce nonce) {
    final msg = source.sessionSharedKey!.readEncryptedMessage(
      msgBytes: msgBytes,
      nonce: nonce,
      taskTypes: task.supportedTypes,
    );

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
      taskCallGuard(() {
        task.handleMessage(msg);
      });
    } else if (msg is Close) {
      logger.d('Received close message');
      close(msg.reason, 'close msg', receivedCloseMsg: true);
    } else if (msg is Application) {
      logger.e('application messages are currently not supported');
    } else {
      throw ProtocolErrorException(
        'Invalid message during task phase. Message type: ${msg.type}',
      );
    }
    return this;
  }

  @protected
  Phase toClientHandshakePhase(CancelReason reason,
      {bool newInitiator = false, ResponderId? responderOverride}) {
    _cancelTask(reason);
    _link.disconnect();
    return onlyCreateClientHandshakePhase(
        initiatorOverride: newInitiator, responderOverride: responderOverride);
  }

  bool _taskCancelWasCalled = false;

  /// Cancels the task.
  ///
  /// This will call [Task.handleCancel] and disconnect the task and client.
  /// This method executes only once, any further calls are ignore.
  ///
  /// This can still cancel a task after the handover was done, which is
  /// important for allowing the user to cancel the client in all situations.
  void _cancelTask(CancelReason reason) {
    // Making sure to only call this once makes it easier for us to reason
    // about failure conditions and makes it easier for the task by guarantee
    // `handleCancel` is only called once.
    if (!_taskCancelWasCalled) {
      _taskCancelWasCalled = true;
      taskCallGuard(() {
        task.handleCancel(reason);
      });
      _link.disconnect();
    }
  }

  @protected
  Phase onlyCreateClientHandshakePhase(
      {bool initiatorOverride = false, ResponderId? responderOverride});
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
    validateResponderId(id.value);
    if (id != pairedClient.id) {
      emitEvent(events.AdditionalResponderEvent(
          events.PeerDisconnected(events.PeerKind.unauthenticated)));
      return this;
    } else {
      emitEvent(events.PeerDisconnected(events.PeerKind.authenticated));
      return toClientHandshakePhase(CancelReason.peerUnavailable);
    }
  }

  @override
  Phase handleSendErrorByDestination(Id destination) {
    if (destination != pairedClient.id) {
      emitEvent(events.AdditionalResponderEvent(
          events.SendingMessageToPeerFailed(events.PeerKind.unauthenticated)));
      return this;
    } else {
      emitEvent(
          events.SendingMessageToPeerFailed(events.PeerKind.authenticated));
      return toClientHandshakePhase(CancelReason.peerUnavailable);
    }
  }

  @override
  Phase handleServerMessage(Message msg) {
    if (msg is NewResponder) {
      if (msg.id == pairedClient.id) {
        // For the client we pretend the responder disconnected (and a new
        // not yet authenticated responder reconnected).
        emitEvent(events.PeerDisconnected(events.PeerKind.authenticated));
        return toClientHandshakePhase(CancelReason.peerOverwrite,
            responderOverride: msg.id);
      } else {
        logger.d('Dropping new responder while in task phase');
        sendDropResponder(msg.id, CloseCode.droppedByInitiator);
      }
    } else {
      logger.w('Unexpected server message type: ${msg.type}');
    }
    return this;
  }

  @override
  Phase onlyCreateClientHandshakePhase(
      {bool initiatorOverride = false, ResponderId? responderOverride}) {
    assert(initiatorOverride == false);
    final newPhase = InitiatorClientHandshakePhase(common, config);
    if (responderOverride != null) {
      newPhase.addNewResponder(responderOverride);
    }
    return newPhase;
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
    validateInitiatorId(id.value);
    emitEvent(events.PeerDisconnected(events.PeerKind.authenticated));
    return toClientHandshakePhase(CancelReason.peerUnavailable);
  }

  @override
  Phase handleSendErrorByDestination(Id destination) {
    emitEvent(events.SendingMessageToPeerFailed(events.PeerKind.authenticated));
    return toClientHandshakePhase(CancelReason.peerUnavailable);
  }

  @override
  Phase handleServerMessage(Message msg) {
    if (msg is NewInitiator) {
      // For the client we pretend the initiator disconnected (and a new
      // not yet authenticated responder reconnected).
      emitEvent(events.PeerDisconnected(events.PeerKind.authenticated));
      return toClientHandshakePhase(CancelReason.peerOverwrite,
          newInitiator: true);
    } else {
      logger.w('Unexpected server message type: ${msg.type}');
      return this;
    }
  }

  @override
  Phase onlyCreateClientHandshakePhase(
      {bool initiatorOverride = false, ResponderId? responderOverride}) {
    assert(responderOverride == null);
    return ResponderClientHandshakePhase(common, config,
        initiatorConnected: initiatorOverride);
  }
}
