import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/src/messages/c2c/common.dart'
    show writeDataTagWithTasksData;
import 'package:dart_saltyrtc_client/src/messages/message.dart'
    show Message, MessageType, MessageFields, TasksData;
import 'package:dart_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;
import 'package:dart_saltyrtc_client/src/messages/validation.dart'
    show
        validateType,
        validateByteArrayType,
        validateByteArray,
        validateTasksDataType,
        validateTasksData,
        validateListType;
import 'package:messagepack/messagepack.dart' show Packer;
import 'package:meta/meta.dart' show immutable;

const _type = MessageType.auth;

@immutable
class AuthResponder extends Message {
  final Uint8List yourCookie;
  final List<String> tasks;
  final TasksData data;

  @override
  List<Object> get props => [yourCookie, tasks, data];

  AuthResponder(this.yourCookie, this.tasks, this.data) {
    validateByteArray(yourCookie, Nonce.cookieLength, MessageFields.yourCookie);
    validateTasksData(tasks, data);
  }

  factory AuthResponder.fromMap(Map<String, Object?> map) {
    validateType(map[MessageFields.type], _type);
    final yourCookie = validateByteArrayType(
        map[MessageFields.yourCookie], MessageFields.yourCookie);
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
      ..packBinary(yourCookie)
      ..packString(MessageFields.tasks)
      ..packListLength(tasks.length);

    for (final task in tasks) {
      msgPacker.packString(task);
    }

    writeDataTagWithTasksData(msgPacker, data);
  }
}