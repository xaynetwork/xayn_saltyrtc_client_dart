import 'package:dart_saltyrtc_client/src/messages/message.dart'
    show Message, MessageType, MessageFields;
import 'package:dart_saltyrtc_client/src/messages/validation.dart'
    show validateType;
import 'package:messagepack/messagepack.dart' show Packer;
import 'package:meta/meta.dart' show immutable;

const _type = MessageType.newInitiator;

@immutable
class NewInitiator extends Message {
  NewInitiator();

  NewInitiator.fromMap(Map<String, dynamic> map) {
    validateType(map[MessageFields.type], _type);
  }

  @override
  String getType() => _type;

  @override
  void write(Packer msgPacker) {
    msgPacker
      ..packMapLength(1)
      ..packString(MessageFields.type)
      ..packString(_type);
  }
}
