import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/src/logger.dart' show logger;
import 'package:dart_saltyrtc_client/src/messages/c2c/application.dart'
    show Application;
import 'package:dart_saltyrtc_client/src/messages/c2c/close.dart' show Close;
import 'package:dart_saltyrtc_client/src/messages/c2c/task_message.dart'
    show TaskMessage;
import 'package:dart_saltyrtc_client/src/messages/close_code.dart'
    show CloseCode, CloseCodeToFromInt;
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
      phase.close(closeCode, reason);
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
      phase.enableHandover();
      phase.close(CloseCode.handover, 'handover');
    } else {
      throw StateError('already disconnected from phase');
    }
  }

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

  @override
  void enableHandover() {
    //ignore: invalid_use_of_protected_member
    common.enableHandover = true;
  }

  void taskCallGuard(void Function() func) {
    try {
      func();
    } catch (e, s) {
      _link.disconnect();
      // Do not use `this.emitEvent` here as we do not want to send this event to
      // the task as this might case further errors or even infinite recursion.
      common.events.emitEvent(events.InternalError(e), s);
      close(CloseCode.internalError, e.toString());
      // We did fall over at some point during the handover,
      // make sure events are closed anyway.
      if (isHandoverEnabled) {
        common.events.close();
      }
      try {
        task.handleCancel(CancelReason.handlerDidThrow);
      } catch (e, s) {
        logger.e(
            'handleCancel(CancelReason.handleDidThrow) did also throw: $e\n$s');
      }
    }
  }

  @override
  void emitEvent(Event event, [StackTrace? st]) {
    taskCallGuard(() {
      task.handleEvent(event);
    });
    if (event is events.HandoverToTask) {
      taskCallGuard(() {
        task.handleHandover(common.events);
        // only emit handover event to client if the handler did not throw
        common.events.emitEvent(event, st);
      });
      _link.disconnect();
    } else {
      common.events.emitEvent(event, st);
    }
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
      return this;
    } else if (msg is Close) {
      logger.d('Received close message');
      return handleClose(msg);
    } else if (msg is Application) {
      return handleApplicationMessage(msg);
    } else {
      throw ProtocolErrorException(
        'Invalid message during task phase. Message type: ${msg.type}',
      );
    }
  }

  @protected
  Phase handleClose(Close msg) {
    final closeCode = msg.reason;
    if (closeCode == CloseCode.handover) {
      enableHandover();
    } else {
      final event = events.eventFromWSCloseCode(closeCode.toInt());
      if (event != null) {
        emitEvent(event);
      }
    }
    close(null, 'close msg');
    return this;
  }

  @protected
  Phase handleApplicationMessage(Application msg) {
    logger.e('application messages are currently not supported');
    return this;
  }

  @protected
  Phase toClientHandshakePhase(CancelReason reason,
      {bool newInitiator = false, ResponderId? responderOverride}) {
    taskCallGuard(() {
      task.handleCancel(reason);
    });
    _link.disconnect();
    return onlyCreateClientHandshakePhase(
        initiatorOverrid: newInitiator, responderOverride: responderOverride);
  }

  @override
  void notifyConnectionClosed() {
    super.notifyConnectionClosed();
    taskCallGuard(() {
      task.handleWSClosed();
    });
  }

  @override
  int? doClose(CloseCode? closeCode) {
    // WARNING: Do not move any task cancellation/closing logic in here.
    //          It would mess with handovers, instead use the `onClosed`
    //          future.
    if (closeCode != null) {
      sendMessage(Close(closeCode), to: pairedClient);
      return CloseCode.goingAway.toInt();
    } else {
      return super.doClose(closeCode);
    }
  }

  @protected
  Phase onlyCreateClientHandshakePhase(
      {bool initiatorOverrid = false, ResponderId? responderOverride});
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
      return toClientHandshakePhase(CancelReason.disconnected);
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
      return toClientHandshakePhase(CancelReason.sendError);
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
      {bool initiatorOverrid = false, ResponderId? responderOverride}) {
    assert(initiatorOverrid == false);
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
    return toClientHandshakePhase(CancelReason.disconnected);
  }

  @override
  Phase handleSendErrorByDestination(Id destination) {
    emitEvent(events.SendingMessageToPeerFailed(events.PeerKind.authenticated));
    return toClientHandshakePhase(CancelReason.sendError);
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
      {bool initiatorOverrid = false, ResponderId? responderOverride}) {
    assert(responderOverride == null);
    return ResponderClientHandshakePhase(common, config,
        initiatorConnected: initiatorOverrid);
  }
}
