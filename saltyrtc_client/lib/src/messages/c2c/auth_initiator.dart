import 'package:messagepack/messagepack.dart' show Packer;
import 'package:meta/meta.dart' show immutable;
import 'package:xayn_saltyrtc_client/src/messages/message.dart'
    show Message, MessageType, MessageFields, TasksData;
import 'package:xayn_saltyrtc_client/src/messages/nonce/cookie.dart'
    show Cookie;
import 'package:xayn_saltyrtc_client/src/messages/validation.dart'
    show
        validateType,
        validateByteArrayType,
        validateTasksDataType,
        validateTasksData,
        validateStringType;
import 'package:xayn_saltyrtc_client/src/msgpack_ext.dart' show PackAnyExt;

const _type = MessageType.auth;

/// Auth message as send by the initiator.
@immutable
class AuthInitiator extends Message {
  /// The cookie of the receiver of the message.
  final Cookie yourCookie;
  final String task;
  final TasksData data;

  @override
  List<Object> get props => [yourCookie, task, data];

  AuthInitiator(this.yourCookie, this.task, this.data) {
    validateTasksData([task], data);
  }

  factory AuthInitiator.fromMap(Map<String, Object?> map) {
    validateType(map[MessageFields.type], _type);
    final yourCookie = Cookie(
      validateByteArrayType(
        map[MessageFields.yourCookie],
        MessageFields.yourCookie,
      ),
    );
    final task =
        validateStringType(map[MessageFields.task], MessageFields.task);
    final data =
        validateTasksDataType(map[MessageFields.data], MessageFields.data);

    return AuthInitiator(yourCookie, task, data);
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
      ..packString(MessageFields.task)
      ..packString(task)
      ..packString(MessageFields.data)
      ..packAny(data);
  }
}
