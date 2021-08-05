import 'dart:typed_data';

import 'package:dart_saltyrtc_client/src/messages/c2c/common.dart'
    show writeStringMapMap;
import 'package:dart_saltyrtc_client/src/messages/message.dart'
    show Message, MessageType, MessageFields, cookieLength;
import 'package:dart_saltyrtc_client/src/messages/validation.dart'
    show
        validateType,
        validateByteArrayType,
        validateByteArray,
        validateStringMapMap,
        validateTasksData,
        validateListType;
import 'package:messagepack/messagepack.dart' show Packer;
import 'package:meta/meta.dart' show immutable;

const _type = MessageType.auth;

@immutable
class AuthResponder extends Message {
  final Uint8List yourCookie;
  final List<String> tasks;
  // See comment on AuthInitiator
  final Map<String, Map<String, List<int>>> data;

  AuthResponder(this.yourCookie, this.tasks, this.data) {
    validateByteArray(yourCookie, cookieLength, MessageFields.yourCookie);
    validateTasksData(tasks, data);
  }

  factory AuthResponder.fromMap(Map<String, dynamic> map) {
    validateType(map[MessageFields.type], _type);
    final yourCookie = validateByteArrayType(
        map[MessageFields.yourCookie], MessageFields.yourCookie);
    final tasks =
        validateListType<String>(map[MessageFields.task], MessageFields.task);
    final data =
        validateStringMapMap(map[MessageFields.data], MessageFields.data);

    return AuthResponder(yourCookie, tasks, data);
  }

  @override
  String getType() => _type;

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

    writeStringMapMap(msgPacker, data);
  }
}
