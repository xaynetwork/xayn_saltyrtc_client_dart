import 'package:dart_saltyrtc_client/src/messages/message.dart' show TaskData;

/// Information that are needed to negotiate and handover a task.
abstract class Task {
  /// Name of the task.
  String get name;

  /// The custom message types that the task use.
  List<String> get supportedTypes;

  /// Data that is sent to the other client during the task negotiation phase.
  ///
  /// For an initiator this is only called after `initialize` was called with the
  /// task data of the responder.
  ///
  /// For a responder this is called *before* init was called.
  TaskData? get data;

  /// Initialize the task for usage.
  void initialize(TaskData? data);
}
