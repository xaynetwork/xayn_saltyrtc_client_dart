import 'dart:typed_data' show Uint8List;

import 'package:messagepack/messagepack.dart' show Packer;
import 'package:meta/meta.dart' show immutable;
import 'package:xayn_saltyrtc_client/src/messages/message.dart'
    show Message, MessageType, MessageFields, signedKeysLength;
import 'package:xayn_saltyrtc_client/src/messages/nonce/cookie.dart'
    show Cookie;
import 'package:xayn_saltyrtc_client/src/messages/validation.dart'
    show
        validateType,
        validateByteArrayType,
        validateByteArray,
        validateBoolType,
        validateTypeWithNull;

const _type = MessageType.serverAuth;

@immutable
class ServerAuthResponder extends Message {
  final Cookie yourCookie;
  final Uint8List? signedKeys;
  final bool initiatorConnected;

  @override
  List<Object?> get props => [yourCookie, signedKeys, initiatorConnected];

  ServerAuthResponder(
      this.yourCookie, this.signedKeys, this.initiatorConnected) {
    if (signedKeys != null) {
      validateByteArray(
          signedKeys!, signedKeysLength, MessageFields.signedKeys);
    }
  }

  factory ServerAuthResponder.fromMap(Map<String, Object?> map) {
    validateType(map[MessageFields.type], _type);
    final yourCookie = Cookie(validateByteArrayType(
        map[MessageFields.yourCookie], MessageFields.yourCookie));
    final initatorConnected = validateBoolType(
        map[MessageFields.initiatorConnected],
        MessageFields.initiatorConnected);

    final signedKeys = validateTypeWithNull(map[MessageFields.signedKeys],
        MessageFields.signedKeys, validateByteArrayType);

    return ServerAuthResponder(yourCookie, signedKeys, initatorConnected);
  }

  @override
  String get type => _type;

  @override
  void write(Packer msgPacker) {
    final hasKeys = signedKeys != null;
    msgPacker
      ..packMapLength(hasKeys ? 4 : 3)
      ..packString(MessageFields.type)
      ..packString(_type)
      ..packString(MessageFields.yourCookie)
      ..packBinary(yourCookie.toBytes())
      ..packString(MessageFields.initiatorConnected)
      ..packBool(initiatorConnected);

    if (hasKeys) {
      msgPacker
        ..packString(MessageFields.signedKeys)
        ..packBinary(signedKeys);
    }
  }
}
