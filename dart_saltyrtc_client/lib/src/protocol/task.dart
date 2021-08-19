import 'package:dart_saltyrtc_client/src/messages/message.dart' show TasksData;

/// Information that are needed to negotiate and handover a task.
abstract class Task {
  /// Name of the task.
  String get name;

  /// The custom message types that the task use.
  List<String> get supportedTypes;

  /// Data that is sent to the other client during the task negotiation phase
  TasksData get data;
}
