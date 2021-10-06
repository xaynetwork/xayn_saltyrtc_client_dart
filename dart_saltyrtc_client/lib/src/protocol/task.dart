import 'package:dart_saltyrtc_client/src/messages/c2c/task_message.dart'
    show TaskMessage;
import 'package:dart_saltyrtc_client/src/messages/close_code.dart'
    show CloseCode;
import 'package:dart_saltyrtc_client/src/messages/message.dart' show TaskData;
import 'package:dart_saltyrtc_client/src/protocol/events.dart'
    show CancelTask, ClosingErrorEvent, Event;

import '../utils.dart' show Pair;

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

  /// Runs the Task
  Future<void> run(SaltyRtcTaskLink link) async {
    try {
      await for (final recvEvent in link.events) {
        final msg = recvEvent.msg;
        if (msg != null) {
          handleMessage(msg);
        }
        final event = recvEvent.event;
        if (event != null) {
          handleEvent(event);
        }
      }
      handleNormalClosing();
    } on CancelTask {
      handleCancelTask();
    } on ClosingErrorEvent catch (e, s) {
      handleErrorClosing(e, s);
    }
  }

  /// Called by the default `run` impl. when a `TaskMessage` is received.
  void handleMessage(TaskMessage msg);

  /// Called by the default `run` impl. when a `Event` was emitted.
  void handleEvent(Event event);

  /// Called by the default `run` impl. once the input `events` stream ended
  /// without an error.
  void handleNormalClosing();

  /// Called by the default `run` impl. once the input `events` stream raised
  /// an error.
  void handleErrorClosing(Object error, StackTrace st);

  /// Called by the default `run` impl. when the `Task` is canceled.
  void handleCancelTask();
}

/// A event as received by the Task.
///
/// This can contain a event emitted by the SaltyRtc client, and/or a
/// message received from the authenticated peer **and/or a cancel task flat**.
class TaskRecvEvent {
  final Event? event;
  final TaskMessage? msg;

  TaskRecvEvent(this.event, this.msg);
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
  void close(CloseCode closeCode);

  /// Emits an event to the application.
  ///
  /// If the event is a instance of `ClosingErrorEvent` the task should
  /// call (or have called) close.
  void emitEvent(Event event);

  /// A stream of events emitted by the SaltyRtc client and task messages
  /// received from the authenticated peer.
  ///
  /// Messages emitted by this instances `emitEvent` will not be re-received
  /// here.
  Stream<TaskRecvEvent> get events;
}
