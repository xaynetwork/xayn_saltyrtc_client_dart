import 'dart:typed_data';

import 'package:dart_saltyrtc_client/src/messages/message.dart'
    show Message, MessageType, MessageFields;
import 'package:dart_saltyrtc_client/src/messages/validation.dart'
    show validateType, validateByteArrayType;
import 'package:messagepack/messagepack.dart' show Packer;
import 'package:meta/meta.dart' show immutable;

const _type = MessageType.application;

@immutable
class Application extends Message {
  final Uint8List data;

  Application(this.data);

  factory Application.fromMap(Map<String, dynamic> map) {
    validateType(map[MessageFields.type], _type);
    final data =
        validateByteArrayType(map[MessageFields.key], MessageFields.key);

    return Application(data);
  }

  @override
  String get type => _type;

  @override
  void write(Packer msgPacker) {
    msgPacker
      ..packMapLength(2)
      ..packString(MessageFields.type)
      ..packString(_type)
      ..packString(MessageFields.data)
      ..packBinary(data);
  }
}
