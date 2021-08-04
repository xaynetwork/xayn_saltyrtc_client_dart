import 'package:messagepack/messagepack.dart' show Packer;
import 'package:meta/meta.dart' show immutable;

import 'package:dart_saltyrtc_client/src/messages/message.dart'
    show Message, MessageType, MessageFields;
import 'package:dart_saltyrtc_client/src/messages/validation.dart'
    show validateType, validateCloseCode, validateIntegerType;

const _type = MessageType.close;

@immutable
class Close extends Message {
  final int reason;

  Close(this.reason) {
    validateCloseCode(reason, false, MessageFields.reason);
  }

  factory Close.fromMap(Map<String, dynamic> map) {
    validateType(map[MessageFields.type], _type);
    final reason =
        validateIntegerType(map[MessageFields.reason], MessageFields.reason);

    return Close(reason);
  }

  @override
  String getType() => _type;

  @override
  void write(Packer msgPacker) {
    msgPacker
      ..packMapLength(2)
      ..packString(MessageFields.type)
      ..packString(_type)
      ..packString(MessageFields.reason)
      ..packInt(reason);
  }
}
