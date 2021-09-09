import 'package:dart_saltyrtc_client/src/messages/message.dart' show TaskData;

/// Information that are needed to negotiate and handover a task.
abstract class Task {
  /// Name of the task.
  String get name;

  /// The custom message types that the task use.
  List<String> get supportedTypes;

  /// Data that is sent to the other client during the task negotiation phase.
  ///
  /// For a initiator this is only called after `init` was called with the
  /// task data of the responder.
  ///
  /// For a responder this is called *before* init was called.
  TaskData? get data;

  /// Initialize the task for usage.
  ///
  //FIXME It MUST be a optional PARSED msgpack map instead, which also can have ANY form.
  void initialize(Map<String, List<int>?>? data) {
    //FIXME remove default impl
    throw UnimplementedError();
  }
}
