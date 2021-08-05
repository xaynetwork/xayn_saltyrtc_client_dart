import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/src/messages/message.dart'
    show Message, MessageType, MessageFields, signedKeysLength;
import 'package:dart_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;
import 'package:dart_saltyrtc_client/src/messages/validation.dart'
    show
        validateType,
        validateByteArrayType,
        validateByteArray,
        validateListType,
        validateIdResponder,
        ValidationError,
        validateTypeWithNull;
import 'package:messagepack/messagepack.dart' show Packer;
import 'package:meta/meta.dart' show immutable;

const _type = MessageType.serverAuth;

@immutable
class ServerAuthInitiator extends Message {
  final Uint8List yourCookie;
  final Uint8List? signedKeys;
  final List<int> responders;

  ServerAuthInitiator(this.yourCookie, this.signedKeys, this.responders) {
    validateByteArray(yourCookie, Nonce.cookieLength, MessageFields.yourCookie);

    if (signedKeys != null) {
      validateByteArray(
          signedKeys!, signedKeysLength, MessageFields.signedKeys);
    }
    for (final id in responders) {
      validateIdResponder(id, MessageFields.responders);
    }
    if (responders.length != responders.toSet().length) {
      throw ValidationError(
          '${MessageFields.responders} must not contain duplicates');
    }
  }

  factory ServerAuthInitiator.fromMap(Map<String, dynamic> map) {
    validateType(map[MessageFields.type], _type);
    final yourCookie = validateByteArrayType(
        map[MessageFields.yourCookie], MessageFields.yourCookie);
    final responders = validateListType<int>(
        map[MessageFields.responders], MessageFields.responders);

    final signedKeys = validateTypeWithNull(map[MessageFields.signedKeys],
        MessageFields.signedKeys, validateByteArrayType);

    return ServerAuthInitiator(yourCookie, signedKeys, responders);
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
      ..packBinary(yourCookie);

    if (hasKeys) {
      msgPacker
        ..packString(MessageFields.signedKeys)
        ..packBinary(signedKeys);
    }

    msgPacker
      ..packString(MessageFields.responders)
      ..packListLength(responders.length);
    for (final responder in responders) {
      msgPacker.packInt(responder);
    }
  }
}
