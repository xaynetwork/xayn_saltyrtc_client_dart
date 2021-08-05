import 'dart:typed_data' show Uint8List;

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
        validateStringType;
import 'package:messagepack/messagepack.dart' show Packer;
import 'package:meta/meta.dart' show immutable;

const _type = MessageType.auth;

@immutable
class AuthInitiator extends Message {
  final Uint8List yourCookie;
  final String task;
  // For each task name we take a Map<String, List<int> to simplify the encoding.
  // We use List<int> and not Uint8List so we don't have to create a new map where
  // we replace List<int> with Uint8List. `unpackBinary` returns List<int>.
  final Map<String, Map<String, List<int>>> data;

  AuthInitiator(this.yourCookie, this.task, this.data) {
    validateByteArray(yourCookie, cookieLength, MessageFields.yourCookie);
    validateTasksData([task], data);
  }

  factory AuthInitiator.fromMap(Map<String, dynamic> map) {
    validateType(map[MessageFields.type], _type);
    final yourCookie = validateByteArrayType(
        map[MessageFields.yourCookie], MessageFields.yourCookie);
    final task =
        validateStringType(map[MessageFields.task], MessageFields.task);
    final data =
        validateStringMapMap(map[MessageFields.data], MessageFields.data);

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
      ..packBinary(yourCookie)
      ..packString(MessageFields.task);

    writeStringMapMap(msgPacker, data);
  }
}
