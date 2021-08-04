import 'dart:typed_data';

import 'package:messagepack/messagepack.dart' show Packer;
import 'package:meta/meta.dart' show immutable;

import 'package:dart_saltyrtc_client/src/messages/message.dart'
    show Message, MessageType, MessageFields;
import 'package:dart_saltyrtc_client/src/messages/validation.dart'
    show validateType, validateByteArrayType, validateByteArray;

const _type = MessageType.sendError;

@immutable
class SendError extends Message {
  final Uint8List id;

  SendError(this.id) {
    // id is the concatenation of the source address (1), the destination address (1),
    // the overflow number (2) and the sequence number (4) (or the combined sequence number)
    // of the nonce section from the original message.
    validateByteArray(id, 8, MessageFields.id);
  }

  factory SendError.fromMap(Map<String, dynamic> map) {
    validateType(map[MessageFields.type], _type);
    final id = validateByteArrayType(map[MessageFields.id], MessageFields.id);

    return SendError(id);
  }

  @override
  String getType() => _type;

  @override
  void write(Packer msgPacker) {
    msgPacker
      ..packMapLength(2)
      ..packString(MessageFields.type)
      ..packString(_type)
      ..packString(MessageFields.id)
      ..packBinary(id);
  }
}
