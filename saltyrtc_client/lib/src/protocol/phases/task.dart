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

import 'package:meta/meta.dart' show protected;
import 'package:xayn_saltyrtc_client/events.dart' as events;
import 'package:xayn_saltyrtc_client/events.dart' show Event;
import 'package:xayn_saltyrtc_client/src/logger.dart' show logger;
import 'package:xayn_saltyrtc_client/src/messages/c2c/application.dart'
    show Application;
import 'package:xayn_saltyrtc_client/src/messages/c2c/close.dart' show Close;
import 'package:xayn_saltyrtc_client/src/messages/c2c/task_message.dart'
    show TaskMessage;
import 'package:xayn_saltyrtc_client/src/messages/close_code.dart'
    show CloseCode;
import 'package:xayn_saltyrtc_client/src/messages/id.dart' show Id, ResponderId;
import 'package:xayn_saltyrtc_client/src/messages/message.dart' show Message;
import 'package:xayn_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;
import 'package:xayn_saltyrtc_client/src/messages/reader.dart'
    show MessageDecryptionExt;
import 'package:xayn_saltyrtc_client/src/messages/s2c/disconnected.dart'
    show Disconnected;
import 'package:xayn_saltyrtc_client/src/messages/s2c/new_initiator.dart'
    show NewInitiator;
import 'package:xayn_saltyrtc_client/src/messages/s2c/new_responder.dart'
    show NewResponder;
import 'package:xayn_saltyrtc_client/src/messages/s2c/send_error.dart'
    show SendError;
import 'package:xayn_saltyrtc_client/src/messages/validation.dart'
    show validateResponderId, validateInitiatorId;
import 'package:xayn_saltyrtc_client/src/protocol/error.dart'
    show ProtocolErrorException;
import 'package:xayn_saltyrtc_client/src/protocol/peer.dart'
    show AuthenticatedInitiator, AuthenticatedResponder, Client, Peer;
import 'package:xayn_saltyrtc_client/src/protocol/phases/client_handshake_initiator.dart'
    show InitiatorClientHandshakePhase;
import 'package:xayn_saltyrtc_client/src/protocol/phases/client_handshake_responder.dart'
    show ResponderClientHandshakePhase;
import 'package:xayn_saltyrtc_client/src/protocol/phases/phase.dart'
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
import 'package:xayn_saltyrtc_client/src/protocol/task.dart'
    show SaltyRtcTaskLink, Task, CancelReason;
import 'package:xayn_saltyrtc_client/src/utils.dart' show EmitEventExt;

class _Link extends SaltyRtcTaskLink {
  TaskPhase? _phase;
  bool handoverStarted = false;

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
    if (handoverStarted) {
      throw StateError('can not send messages after requesting handover');
    }
    final phase = _phase;
    if (phase != null) {
      phase.sendMessage(msg, to: phase.pairedClient);
    }
  }

  @override
  void requestHandover() {
    final phase = _phase;
    if (phase != null) {
      handoverStarted = true;
      phase.close(CloseCode.handover, 'handover');
    } else {
      throw StateError('already disconnected from phase');
    }
  }

  /// Disconnects task from the client.
  ///
  /// This means the task can no longer access the client.
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
    //ignore: invalid_use_of_protected_member
    task.link = _link;
    taskCallGuard(() {
      task.start();
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
  void cancelTask({bool serverDisconnected = false}) {
    _cancelTask(
      serverDisconnected
          ? CancelReason.serverDisconnected
          : CancelReason.closing,
    );
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
  Phase toClientHandshakePhase(
    CancelReason reason, {
    bool newInitiator = false,
    ResponderId? responderOverride,
  }) {
    _cancelTask(reason);
    _link.disconnect();
    return onlyCreateClientHandshakePhase(
      initiatorOverride: newInitiator,
      responderOverride: responderOverride,
    );
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
    // `handleCancel` is only called once. (It can for example happen in case
    // `cancelTask` throws an exception in which case `killBecauseOf` is called
    // which also calls `cancelTask` as it doesn't know that it was called
    // because of it. And with this fuse it's completely fine and we don't need
    // to propagate what function did throw to `killBecauseOf`).
    if (!_taskCancelWasCalled) {
      _taskCancelWasCalled = true;
      taskCallGuard(() {
        task.handleCancel(reason);
      });
      _link.disconnect();
    }
  }

  @protected
  Phase onlyCreateClientHandshakePhase({
    bool initiatorOverride = false,
    ResponderId? responderOverride,
  });
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
      emitEvent(
        events.AdditionalResponderEvent(
          events.PeerDisconnected(events.PeerKind.unauthenticated),
        ),
      );
      return this;
    } else {
      emitEvent(events.PeerDisconnected(events.PeerKind.authenticated));
      return toClientHandshakePhase(CancelReason.peerUnavailable);
    }
  }

  @override
  Phase handleSendErrorByDestination(Id destination) {
    if (destination != pairedClient.id) {
      emitEvent(
        events.AdditionalResponderEvent(
          events.SendingMessageToPeerFailed(events.PeerKind.unauthenticated),
        ),
      );
      return this;
    } else {
      emitEvent(
        events.SendingMessageToPeerFailed(events.PeerKind.authenticated),
      );
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
        return toClientHandshakePhase(
          CancelReason.peerOverwrite,
          responderOverride: msg.id,
        );
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
  Phase onlyCreateClientHandshakePhase({
    bool initiatorOverride = false,
    ResponderId? responderOverride,
  }) {
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
      return toClientHandshakePhase(
        CancelReason.peerOverwrite,
        newInitiator: true,
      );
    } else {
      logger.w('Unexpected server message type: ${msg.type}');
      return this;
    }
  }

  @override
  Phase onlyCreateClientHandshakePhase({
    bool initiatorOverride = false,
    ResponderId? responderOverride,
  }) {
    assert(responderOverride == null);
    return ResponderClientHandshakePhase(
      common,
      config,
      initiatorConnected: initiatorOverride,
    );
  }
}
