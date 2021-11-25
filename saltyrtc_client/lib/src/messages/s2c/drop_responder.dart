import 'package:messagepack/messagepack.dart' show Packer;
import 'package:meta/meta.dart' show immutable;
import 'package:xayn_saltyrtc_client/src/messages/close_code.dart'
    show CloseCode, CloseCodeToFromInt;
import 'package:xayn_saltyrtc_client/src/messages/id.dart' show ResponderId, Id;
import 'package:xayn_saltyrtc_client/src/messages/message.dart'
    show Message, MessageType, MessageFields;
import 'package:xayn_saltyrtc_client/src/messages/validation.dart'
    show validateType, validateCloseCodeType, validateIntegerType;

const _type = MessageType.dropResponder;

@immutable
class DropResponder extends Message {
  final ResponderId id;
  final CloseCode? reason;

  @override
  List<Object?> get props => [id, reason];

  DropResponder(this.id, this.reason);

  factory DropResponder.fromMap(Map<String, Object?> map) {
    validateType(map[MessageFields.type], _type);

    final id = Id.responderId(
      validateIntegerType(map[MessageFields.id], MessageFields.id),
    );
    final reasonValue = map[MessageFields.reason];
    final reason = reasonValue == null
        ? null
        : validateCloseCodeType(reasonValue, true, MessageFields.reason);

    return DropResponder(id, reason);
  }

  @override
  String get type => _type;

  @override
  void write(Packer msgPacker) {
    final hasReason = reason != null;
    msgPacker
      ..packMapLength(hasReason ? 3 : 2)
      ..packString(MessageFields.type)
      ..packString(_type)
      ..packString(MessageFields.id)
      ..packInt(id.value);

    if (hasReason) {
      msgPacker
        ..packString(MessageFields.reason)
        ..packInt(reason!.toInt());
    }
  }
}
