import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/src/messages/message.dart'
    show Message, MessageType, MessageFields;
import 'package:dart_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;
import 'package:dart_saltyrtc_client/src/messages/validation.dart'
    show
        validateType,
        validateByteArrayType,
        validateByteArray,
        validateListType,
        validateIntegerType,
        validateInteger;
import 'package:messagepack/messagepack.dart' show Packer;
import 'package:meta/meta.dart' show immutable;

const _type = MessageType.clientAuth;

@immutable
class ClientAuth extends Message {
  final Uint8List yourCookie;
  final Uint8List? yourKey;
  final List<String> subprotocols;
  final int pingInterval;

  @override
  List<Object?> get props => [yourCookie, yourKey, subprotocols, pingInterval];

  ClientAuth(
      this.yourCookie, this.yourKey, this.subprotocols, this.pingInterval) {
    const yourKeyLength = 32;
    validateByteArray(yourCookie, Nonce.cookieLength, MessageFields.yourCookie);
    validateInteger(pingInterval, 0, 1 << 31, MessageFields.pingInterval);

    if (yourKey != null) {
      validateByteArray(yourKey!, yourKeyLength, MessageFields.yourKey);
    }
  }

  factory ClientAuth.fromMap(Map<String, Object?> map) {
    validateType(map[MessageFields.type], _type);
    final yourCookie = validateByteArrayType(
        map[MessageFields.yourCookie], MessageFields.yourCookie);
    final subprotocols = validateListType<String>(
        map[MessageFields.subprotocols], MessageFields.subprotocols);
    final pingInterval = validateIntegerType(
        map[MessageFields.pingInterval], MessageFields.pingInterval);

    final yourKeyValue = map[MessageFields.yourKey];
    final yourKey = yourKeyValue == null
        ? null
        : validateByteArrayType(yourKeyValue, MessageFields.yourKey);

    return ClientAuth(yourCookie, yourKey, subprotocols, pingInterval);
  }

  @override
  String get type => _type;

  @override
  void write(Packer msgPacker) {
    final hasKey = yourKey != null;
    msgPacker
      ..packMapLength(hasKey ? 5 : 4)
      ..packString(MessageFields.type)
      ..packString(_type)
      ..packString(MessageFields.yourCookie)
      ..packBinary(yourCookie)
      ..packString(MessageFields.pingInterval)
      ..packInt(pingInterval);
    if (hasKey) {
      msgPacker
        ..packString(MessageFields.yourKey)
        ..packBinary(yourKey);
    }

    msgPacker
      ..packString(MessageFields.subprotocols)
      ..packListLength(subprotocols.length);
    for (final subprotocol in subprotocols) {
      msgPacker.packString(subprotocol);
    }
  }
}
