import 'package:dart_saltyrtc_client/src/messages/close_code.dart'
    show CloseCode, CloseCodeToFromInt;
import 'package:dart_saltyrtc_client/src/messages/message.dart'
    show Message, MessageType, MessageFields;
import 'package:dart_saltyrtc_client/src/messages/validation.dart'
    show validateType, validateCloseCodeType;
import 'package:messagepack/messagepack.dart' show Packer;
import 'package:meta/meta.dart' show immutable;

const _type = MessageType.close;

@immutable
class Close extends Message {
  final CloseCode reason;

  @override
  List<Object> get props => [reason];

  Close(this.reason);

  factory Close.fromMap(Map<String, Object?> map) {
    validateType(map[MessageFields.type], _type);
    final reason = validateCloseCodeType(
        map[MessageFields.reason], false, MessageFields.reason);

    return Close(reason);
  }

  @override
  String get type => _type;

  @override
  void write(Packer msgPacker) {
    msgPacker
      ..packMapLength(2)
      ..packString(MessageFields.type)
      ..packString(_type)
      ..packString(MessageFields.reason)
      ..packInt(reason.toInt());
  }
}
