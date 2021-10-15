import 'dart:async' show EventSink;

import 'package:dart_saltyrtc_client/src/messages/c2c/task_message.dart'
    show TaskMessage;
import 'package:dart_saltyrtc_client/src/messages/close_code.dart'
    show CloseCode;
import 'package:dart_saltyrtc_client/src/messages/message.dart' show TaskData;
import 'package:dart_saltyrtc_client/src/protocol/events.dart' show Event;
import 'package:dart_saltyrtc_client/src/utils.dart' show Pair;

/// Information that are needed to negotiate and handover a task.
///
/// The idea behind the task initialization handshake embedded into
/// the client to client authentication handshake is following:
///
/// 1. The responder gets the data from `getInitialResponderData()` for every
///    task and sends it to the initiator (as part of the auth message).
/// 2. The initiator selects a supported task, ignoring the data in this step.
/// 3. The initiator builds a instance of the selected task using the data
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

/// Type representing a initialized/running task.
abstract class Task {
  /// The custom message types that the task use.
  List<String> get supportedTypes;

  /// Start given task
  void start(SaltyRtcTaskLink link);

  /// Called when a `TaskMessage` is received.
  void handleMessage(TaskMessage msg);

  /// Called when a `Event` was emitted.
  void handleEvent(Event event);

  /// Called once the input `events` stream ended.
  ///
  /// This is guaranteed to be called when the original
  /// WebSocket is closed, even if it's on context of a
  /// handover. (But [handleHandover] will be called first.)
  void handleWSClosed();

  /// Called when the task needs to stop, but the connection is not closed.
  void handleCancel(CancelReason reason);

  /// Called when a handover is started.
  ///
  /// From now on the task is responsible for closing events when it's done or
  /// failed.
  void handleHandover(EventSink<Event> events);
}

enum CancelReason { disconnected, sendError, peerOverwrite }

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
  /// If the event is a instance of `ClosingErrorEvent` the task should
  /// call (or have called) close.
  void emitEvent(Event event);

  /// Trigger a handover.
  ///
  /// This will load to [Task.handleHandover] being called. It might be called
  /// before [requestHandover] returns or it might be called from a later micro
  /// task.
  ///
  void requestHandover();
}
