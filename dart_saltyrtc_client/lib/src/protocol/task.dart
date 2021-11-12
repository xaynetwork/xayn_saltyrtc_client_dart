import 'package:dart_saltyrtc_client/events.dart' show Event;
import 'package:dart_saltyrtc_client/src/messages/c2c/task_message.dart'
    show TaskMessage;
import 'package:dart_saltyrtc_client/src/messages/close_code.dart'
    show CloseCode;
import 'package:dart_saltyrtc_client/src/messages/message.dart' show TaskData;
import 'package:dart_saltyrtc_client/src/utils.dart' show Pair;
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
///
/// Be aware that `TaskBuilder` instances are reused if a failure doesn't cause
/// the connection to be closed. Even if they were already used to create a
/// `Task`.
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

/// Type representing the interface of an initialized/running task.
///
/// # Async, I/O and Tasks
///
/// Task implementation can do async operations including I/O independent of
/// the client, to some degree that is the point of a Task.
///
/// But it needs to follow some rules:
///
/// - It should not do any async operations, I/O and similar before start was
///   called.
/// - It should stop any async operation, I/O and similar when
///   [Task.handleCancel] is call.
abstract class Task {
  /// The link to the `TaskPhase`.
  ///
  /// It's automatically set before `start` is called,
  /// you can not access it before it.
  @protected
  late SaltyRtcTaskLink link;

  /// The custom message types that the task use.
  List<String> get supportedTypes;

  /// Start given task.
  ///
  /// Once the task is done [SaltyRtcTaskLink.close] must be called.
  void start();

  /// Called when a `TaskMessage` is received.
  void handleMessage(TaskMessage msg);

  /// Called when an `Event` was emitted by the client.
  ///
  /// # The `HandoverToTask` event.
  ///
  /// This is emitted after the original WebSocket is already closed,
  /// it's not possible to cancel a handover.
  ///
  /// Once the event is emitted using [SaltyRtcTaskLink.sendMessage] will
  /// throw an [Error].
  void handleEvent(Event event);

  /// Called when the task needs to stop.
  ///
  /// Depending on the `reason` the WebSocket and/or `events` sink might
  /// already have been closed.
  ///
  /// The task will be "disconnected" from the client immediately after this
  /// handler returns, i.e. once the handler returns sending messages or
  /// emitting events or calling `close` through the link will no longer work.
  void handleCancel(CancelReason reason);
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
  /// After this is called using [SaltyRtcTaskLink.sendMessage] will
  /// throw an [Error].
  void requestHandover();
}
