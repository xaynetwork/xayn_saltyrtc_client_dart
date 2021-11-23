import 'package:messagepack/messagepack.dart' show Packer;
import 'package:meta/meta.dart' show immutable;
import 'package:xayn_saltyrtc_client/src/messages/id.dart' show ResponderId, Id;
import 'package:xayn_saltyrtc_client/src/messages/message.dart'
    show Message, MessageType, MessageFields;
import 'package:xayn_saltyrtc_client/src/messages/validation.dart'
    show validateType, validateIntegerType;

const _type = MessageType.newResponder;

@immutable
class NewResponder extends Message {
  final ResponderId id;

  @override
  List<Object> get props => [id];

  NewResponder(this.id);

  factory NewResponder.fromMap(Map<String, Object?> map) {
    validateType(map[MessageFields.type], _type);

    final id = Id.responderId(
        validateIntegerType(map[MessageFields.id], MessageFields.id));

    return NewResponder(id);
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
      ..packInt(id.value);
  }
}
