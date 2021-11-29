import 'package:messagepack/messagepack.dart' show Packer;
import 'package:meta/meta.dart' show immutable;
import 'package:xayn_saltyrtc_client/src/messages/message.dart'
    show Message, MessageFields;
import 'package:xayn_saltyrtc_client/src/messages/validation.dart'
    show validateTypeType;
import 'package:xayn_saltyrtc_client/src/msgpack_ext.dart' show PackAnyExt;

@immutable
class TaskMessage extends Message {
  @override
  final String type;
  final Map<String, Object?> data;

  @override
  List<Object?> get props => [type, data];

  TaskMessage(this.type, this.data) {
    if (data.containsKey(MessageFields.type)) {
      throw ArgumentError(
        'task message data must not contain ${MessageFields.type} field',
      );
    }
  }

  factory TaskMessage.fromMap(Map<String, Object?> map) {
    final type = validateTypeType(map[MessageFields.type]);
    final mapCopy = Map.of(map);
    mapCopy.remove(MessageFields.type);
    return TaskMessage(type, mapCopy);
  }

  @override
  void write(Packer msgPacker) {
    final copyOfData = Map.of(data);
    copyOfData[MessageFields.type] = type;
    msgPacker.packAny(copyOfData);
  }
}
