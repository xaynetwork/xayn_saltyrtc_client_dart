import 'package:dart_saltyrtc_client/src/messages/close_code.dart'
    show CloseCode, CloseCodeToFromInt;
import 'package:dart_saltyrtc_client/src/messages/message.dart'
    show Message, MessageType, MessageFields;
import 'package:dart_saltyrtc_client/src/messages/validation.dart'
    show validateType, validateId, validateCloseCodeType, validateIntegerType;
import 'package:messagepack/messagepack.dart' show Packer;
import 'package:meta/meta.dart' show immutable;

const _type = MessageType.dropResponder;

@immutable
class DropResponder extends Message {
  final int id;
  final CloseCode? reason;

  DropResponder(this.id, this.reason) {
    validateId(id);
  }

  factory DropResponder.fromMap(Map<String, dynamic> map) {
    validateType(map[MessageFields.type], _type);

    final id = validateIntegerType(map[MessageFields.id], MessageFields.id);
    final dynamic reasonValue = map[MessageFields.reason];
    final reason = reasonValue == null
        ? null
        : validateCloseCodeType(reasonValue, true, MessageFields.reason);

    return DropResponder(id, reason);
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
      ..packInt(id);

    if (reason != null) {
      msgPacker
        ..packString(MessageFields.reason)
        ..packInt(reason!.toInt());
    }
  }
}
