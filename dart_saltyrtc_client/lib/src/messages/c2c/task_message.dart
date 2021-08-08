import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/src/messages/message.dart'
    show Message, MessageFields;
import 'package:dart_saltyrtc_client/src/messages/validation.dart'
    show validateTypeType, validateStringBytesMapType;
import 'package:messagepack/messagepack.dart' show Packer;
import 'package:meta/meta.dart' show immutable;

@immutable
class TaskMessage extends Message {
  @override
  final String type;
  final Map<String, Uint8List> data;

  @override
  List<Object> get props => [type, data];

  TaskMessage(this.type, this.data);

  factory TaskMessage.fromMap(Map<String, dynamic> map) {
    final type = validateTypeType(map[MessageFields.type]);
    final data =
        validateStringBytesMapType(map[MessageFields.data], MessageFields.data);

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
