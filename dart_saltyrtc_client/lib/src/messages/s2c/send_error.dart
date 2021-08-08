import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/src/messages/message.dart'
    show Message, MessageType, MessageFields;
import 'package:dart_saltyrtc_client/src/messages/validation.dart'
    show validateType, validateByteArrayType, validateByteArray;
import 'package:equatable/equatable.dart';
import 'package:messagepack/messagepack.dart' show Packer;
import 'package:meta/meta.dart' show immutable;

const _type = MessageType.sendError;

@immutable
class SendError extends Message with EquatableMixin {
  // id is the concatenation of the source address (1), the destination address (1),
  // the overflow number (2) and the sequence number (4) (or the combined sequence number)
  // of the nonce section from the original message.
  static const idLength = 8;
  final Uint8List id;

  @override
  List<Object> get props => [id];

  SendError(this.id) {
    validateByteArray(id, idLength, MessageFields.id);
  }

  factory SendError.fromMap(Map<String, dynamic> map) {
    validateType(map[MessageFields.type], _type);
    final id = validateByteArrayType(map[MessageFields.id], MessageFields.id);

    return SendError(id);
  }

  @override
  String get type => _type;

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
