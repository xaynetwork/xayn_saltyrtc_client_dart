import 'package:messagepack/messagepack.dart' show Packer;
import 'package:meta/meta.dart' show immutable;

import 'package:dart_saltyrtc_client/src/messages/message.dart'
    show Message, MessageType, MessageFields;
import 'package:dart_saltyrtc_client/src/messages/validation.dart'
    show validateType, validateId, validateCloseCode, validateIntegerType;

const _type = MessageType.dropResponder;

@immutable
class DropResponder extends Message {
  final int id;
  final int? reason;

  DropResponder(this.id, this.reason) {
    validateId(id);
    if (reason != null) {
      validateCloseCode(reason!, true, MessageFields.reason);
    }
  }

  factory DropResponder.fromMap(Map<String, dynamic> map) {
    validateType(map[MessageFields.type], _type);

    final id = validateIntegerType(map[MessageFields.id], MessageFields.id);
    final reasonValue = map[MessageFields.reason];
    final reason = reasonValue == null
        ? null
        : validateIntegerType(reasonValue, MessageFields.reason);

    return DropResponder(id, reason);
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
      ..packInt(id);
  }
}
