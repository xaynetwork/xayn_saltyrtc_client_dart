import 'dart:typed_data';

import 'package:messagepack/messagepack.dart' show Packer;
import 'package:meta/meta.dart' show immutable;

import 'package:dart_saltyrtc_client/src/messages/message.dart'
    show Message, MessageFields;

@immutable
class TaskMessage extends Message {
  final String type;
  final Map<String, Uint8List> data;

  TaskMessage(this.type, this.data);

  @override
  String getType() => type;

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
