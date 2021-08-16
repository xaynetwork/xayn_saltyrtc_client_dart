import 'package:dart_saltyrtc_client/src/messages/message.dart'
    show Message, MessageFields, TaskData;
import 'package:dart_saltyrtc_client/src/messages/validation.dart'
    show validateTypeType, validateTaskDataType;
import 'package:messagepack/messagepack.dart' show Packer;
import 'package:meta/meta.dart' show immutable;

@immutable
class TaskMessage extends Message {
  @override
  final String type;
  final TaskData data;

  @override
  List<Object> get props => [type, data];

  TaskMessage(this.type, this.data);

  factory TaskMessage.fromMap(Map<String, Object?> map) {
    final type = validateTypeType(map[MessageFields.type]);
    final data =
        validateTaskDataType(map[MessageFields.data], MessageFields.data);

    return TaskMessage(type, data);
  }

  @override
  void write(Packer msgPacker) {
    msgPacker
      ..packMapLength(2)
      ..packString(MessageFields.type)
      ..packString(type)
      ..packMapLength(data.length);

    data.forEach((key, value) {
      msgPacker
        ..packString(key)
        ..packBinary(value);
    });
  }
}
