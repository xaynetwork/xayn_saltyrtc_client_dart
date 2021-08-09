import 'package:dart_saltyrtc_client/src/messages/message.dart'
    show Message, MessageType, MessageFields;
import 'package:dart_saltyrtc_client/src/messages/validation.dart'
    show validateType, validateIdPeer, validateIntegerType;
import 'package:messagepack/messagepack.dart' show Packer;
import 'package:meta/meta.dart' show immutable;

const _type = MessageType.disconnected;

@immutable
class Disconnected extends Message {
  final int id;

  Disconnected(this.id) {
    // An initiator should validate that the id is a responder.
    // A responder should validate the id to be 1.
    // Here we validate the rage 1 <= id <= 255.
    validateIdPeer(id);
  }

  factory Disconnected.fromMap(Map<String, dynamic> map) {
    validateType(map[MessageFields.type], _type);
    final id = validateIntegerType(map[MessageFields.id], MessageFields.id);

    return Disconnected(id);
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
  }
}
