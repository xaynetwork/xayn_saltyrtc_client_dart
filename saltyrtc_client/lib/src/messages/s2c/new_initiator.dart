import 'package:messagepack/messagepack.dart' show Packer;
import 'package:meta/meta.dart' show immutable;
import 'package:xayn_saltyrtc_client/src/messages/message.dart'
    show Message, MessageType, MessageFields;
import 'package:xayn_saltyrtc_client/src/messages/validation.dart'
    show validateType;

const _type = MessageType.newInitiator;

@immutable
class NewInitiator extends Message {
  NewInitiator();

  @override
  List<Object> get props => [];

  NewInitiator.fromMap(Map<String, Object?> map) {
    validateType(map[MessageFields.type], _type);
  }

  @override
  String get type => _type;

  @override
  void write(Packer msgPacker) {
    msgPacker
      ..packMapLength(1)
      ..packString(MessageFields.type)
      ..packString(_type);
  }
}