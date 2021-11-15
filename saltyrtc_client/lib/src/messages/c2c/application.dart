import 'dart:typed_data' show Uint8List;

import 'package:messagepack/messagepack.dart' show Packer;
import 'package:meta/meta.dart' show immutable;
import 'package:xayn_saltyrtc_client/src/messages/message.dart'
    show Message, MessageType, MessageFields;
import 'package:xayn_saltyrtc_client/src/messages/validation.dart'
    show validateType, validateByteArrayType;

const _type = MessageType.application;

@immutable
class Application extends Message {
  final Uint8List data;

  @override
  List<Object> get props => [data];

  Application(this.data);

  factory Application.fromMap(Map<String, Object?> map) {
    validateType(map[MessageFields.type], _type);
    final data =
        validateByteArrayType(map[MessageFields.data], MessageFields.data);

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