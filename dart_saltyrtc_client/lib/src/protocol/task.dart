import 'dart:async' show EventSink;

import 'package:dart_saltyrtc_client/src/messages/c2c/task_message.dart'
    show TaskMessage;
import 'package:dart_saltyrtc_client/src/messages/close_code.dart'
    show CloseCode;
import 'package:dart_saltyrtc_client/src/messages/message.dart' show TaskData;
import 'package:dart_saltyrtc_client/src/protocol/events.dart' show Event;
import 'package:dart_saltyrtc_client/src/utils.dart' show EmitEventExt, Pair;
import 'package:meta/meta.dart' show protected;

/// Information that are needed to negotiate and handover a task.
///
/// The idea behind the task initialization handshake embedded into
/// the client to client authentication handshake is following:
///
/// 1. The responder gets the data from `getInitialResponderData()` for every
///    task and sends it to the initiator (as part of the auth message).
/// 2. The initiator selects a supported task, ignoring the data in this step.
/// 3. The initiator builds an instance of the selected task using the data
///    provided from the responder. Besides the `Task` instance this will create
///    data which is send back to the responder (as part of the auth message).
/// 4. The responder creates a task instance based on the data returned from
///    the initiator.
abstract class TaskBuilder {
  /// Name of the task.
  String get name;

  /// The data a responder uses to start negotiating the task setup.
  TaskData? getInitialResponderData();

  /// Create a task instance for the initiator.
  Pair<Task, TaskData?> buildInitiatorTask(TaskData? initialResponderData);

  /// Create a task instance for the responder.
  Task buildResponderTask(TaskData? initiatorData);
}

/// Type representing an initialized/running task.
///
/// This trait contains some default implementations to reduce some overhead
/// for task implementors.
abstract class Task {
  /// The custom message types that the task use.
  List<String> get supportedTypes;

  /// Start given task
  void start(SaltyRtcTaskLink link) {
    this.link = link;
  }

  /// Called when a `TaskMessage` is received.
  void handleMessage(TaskMessage msg);

  /// Called when an `Event` was emitted.
  ///
  /// As not all tasks need to listen for events this
  /// has an empty default implementation.
  void handleEvent(Event event) {}

  /// Called when the task needs to stop.
  ///
  /// Depending on the `reason` the WebSocket and/or `events` sink might
  /// already have been closed.
  ///
  /// The task will be "disconnected" from the client immediately after this
  /// handler returns, i.e. once the handler returns sending messages or
  /// emitting events through the link will no longer work.
  void handleCancel(CancelReason reason);

  /// Called after the handover is started.
  ///
  /// From now on the task is responsible for closing the events sink
  /// when it's done (independent of weather it succeeds, fails or is
  /// canceled).
  ///
  /// This is called after the original WebSocket is already closed,
  /// it's not possible to cancel a handover.
  ///
  /// The default implementation stores `events` so that `handoverWasDone`
  /// returns `true`, for some tasks this might be all they need.
  void handleHandover(EventSink<Event> events) {
    _eventsPostHandover = events;
  }

  @protected
  EventSink<Event>? get eventsPostHandover => _eventsPostHandover;
  EventSink<Event>? _eventsPostHandover;

  @protected
  bool get handoverWasDone => _eventsPostHandover != null;

  @protected
  late SaltyRtcTaskLink link;

  @protected
  void emitEvent(Event event) {
    final eventsPostHandover = this.eventsPostHandover;
    if (eventsPostHandover != null) {
      eventsPostHandover.emitEvent(event);
    } else {
      link.emitEvent(event);
    }
  }
}

enum CancelReason {
  /// The server can not deliver messages to the peer anymore.
  peerUnavailable,

  /// The peer was replaced with a new peer.
  peerOverwrite,

  /// WebSocket closed without a handover.
  ///
  /// When this is called the WebSocket is already closed. The
  /// event sink is still open (it will be closed immediately after this
  /// handler is called).
  serverDisconnected,

  /// The client is closing, so the task needs to be canceled.
  ///
  /// In difference to the other reason this can still happen after
  /// [Task.handleHandover] was called and must still be handled by
  /// canceling the task.
  closing
}

/// Links the Task and the SaltyRtc client together.
///
/// A Task should listen on `events` (as done in the
/// default `run` implementation) and can send messages,
/// custom events and close the stream through methods
/// on this type.
abstract class SaltyRtcTaskLink {
  /// Sends a task message to the authenticated peer.
  void sendMessage(TaskMessage msg);

  /// Closes the client.
  ///
  /// This will send a `Close` message with the given close code to the peer,
  /// then it will close the WebRtc socket using `1001` (Going Away) as status
  /// code.
  void close(CloseCode closeCode, [String? reason]);

  /// Emits an event to the application.
  ///
  /// If the event is an instance of `ClosingErrorEvent` the task should
  /// call (or have called) close.
  void emitEvent(Event event);

  /// Trigger a handover.
  ///
  /// This will lead to [necessary.handleHandover] being called. It might be called
  /// before [requestHandover] returns or it might be called it might be called
  /// async on a later tick.
  ///
  void requestHandover();
}
