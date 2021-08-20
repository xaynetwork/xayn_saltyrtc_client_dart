import 'package:dart_saltyrtc_client/src/messages/id.dart' show IdResponder, Id;
import 'package:dart_saltyrtc_client/src/messages/message.dart'
    show Message, MessageType, MessageFields;
import 'package:dart_saltyrtc_client/src/messages/validation.dart'
    show validateType, validateIntegerType;
import 'package:messagepack/messagepack.dart' show Packer;
import 'package:meta/meta.dart' show immutable;

const _type = MessageType.newResponder;

@immutable
class NewResponder extends Message {
  final IdResponder id;

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
