import 'package:dart_saltyrtc_client/src/messages/message.dart' show TaskData;

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
}
