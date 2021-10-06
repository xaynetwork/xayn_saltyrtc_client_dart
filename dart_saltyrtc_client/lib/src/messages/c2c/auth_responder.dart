import 'package:dart_saltyrtc_client/src/messages/message.dart'
    show Message, MessageType, MessageFields, TasksData;
import 'package:dart_saltyrtc_client/src/messages/nonce/cookie.dart'
    show Cookie;
import 'package:dart_saltyrtc_client/src/messages/validation.dart'
    show
        validateType,
        validateByteArrayType,
        validateTasksDataType,
        validateTasksData,
        validateListType;
import 'package:dart_saltyrtc_client/src/msgpack_ext.dart';
import 'package:messagepack/messagepack.dart' show Packer;
import 'package:meta/meta.dart' show immutable;

const _type = MessageType.auth;

/// Auth message as send by the responder.
@immutable
class AuthResponder extends Message {
  final Cookie yourCookie;
  final List<String> tasks;
  final TasksData data;

  @override
  List<Object> get props => [yourCookie, tasks, data];

  AuthResponder(this.yourCookie, this.tasks, this.data) {
    validateTasksData(tasks, data);
  }

  factory AuthResponder.fromMap(Map<String, Object?> map) {
    validateType(map[MessageFields.type], _type);
    final yourCookie = Cookie(validateByteArrayType(
        map[MessageFields.yourCookie], MessageFields.yourCookie));
    final tasks =
        validateListType<String>(map[MessageFields.tasks], MessageFields.tasks);
    final data =
        validateTasksDataType(map[MessageFields.data], MessageFields.data);

    return AuthResponder(yourCookie, tasks, data);
  }

  @override
  String get type => _type;

  @override
  void write(Packer msgPacker) {
    msgPacker
      ..packMapLength(4)
      ..packString(MessageFields.type)
      ..packString(_type)
      ..packString(MessageFields.yourCookie)
      ..packBinary(yourCookie.toBytes())
      ..packString(MessageFields.tasks)
      ..packListLength(tasks.length);

    for (final task in tasks) {
      msgPacker.packString(task);
    }

    msgPacker
      ..packString(MessageFields.data)
      ..packAny(data);
  }
}
