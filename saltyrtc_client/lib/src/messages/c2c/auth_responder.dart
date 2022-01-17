// Copyright 2021 Xayn AG
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

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
        validateListType;
import 'package:xayn_saltyrtc_client/src/msgpack_ext.dart' show PackAnyExt;

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
    final yourCookie = Cookie(
      validateByteArrayType(
        map[MessageFields.yourCookie],
        MessageFields.yourCookie,
      ),
    );
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
