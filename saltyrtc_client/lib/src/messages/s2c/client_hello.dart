import 'dart:typed_data' show Uint8List;

import 'package:messagepack/messagepack.dart' show Packer;
import 'package:meta/meta.dart' show immutable;
import 'package:xayn_saltyrtc_client/src/crypto/crypto.dart' show Crypto;
import 'package:xayn_saltyrtc_client/src/messages/message.dart'
    show Message, MessageType, MessageFields;
import 'package:xayn_saltyrtc_client/src/messages/validation.dart'
    show validateType, validateByteArrayType, validateByteArray;

const _type = MessageType.clientHello;

@immutable
class ClientHello extends Message {
  final Uint8List key;

  @override
  List<Object> get props => [key];

  ClientHello(this.key) {
    validateByteArray(key, Crypto.publicKeyBytes, MessageFields.key);
  }

  factory ClientHello.fromMap(Map<String, Object?> map) {
    validateType(map[MessageFields.type], _type);
    final key =
        validateByteArrayType(map[MessageFields.key], MessageFields.key);

    return ClientHello(key);
  }

  @override
  String get type => _type;

  @override
  void write(Packer msgPacker) {
    msgPacker
      ..packMapLength(2)
      ..packString(MessageFields.type)
      ..packString(_type)
      ..packString(MessageFields.key)
      ..packBinary(key);
  }
}