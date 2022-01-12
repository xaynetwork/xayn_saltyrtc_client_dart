// Copyright 2021 Xayn AG
//
// Licensed under the Apache License, Version 2.0 (the License);
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'package:messagepack/messagepack.dart' show Packer;
import 'package:meta/meta.dart' show immutable;
import 'package:xayn_saltyrtc_client/src/messages/close_code.dart'
    show CloseCode, CloseCodeToFromInt;
import 'package:xayn_saltyrtc_client/src/messages/message.dart'
    show Message, MessageType, MessageFields;
import 'package:xayn_saltyrtc_client/src/messages/validation.dart'
    show validateType, validateCloseCodeType;

const _type = MessageType.close;

@immutable
class Close extends Message {
  final CloseCode reason;

  @override
  List<Object> get props => [reason];

  Close(this.reason);

  factory Close.fromMap(Map<String, Object?> map) {
    validateType(map[MessageFields.type], _type);
    final reason = validateCloseCodeType(
      map[MessageFields.reason],
      false,
      MessageFields.reason,
    );

    return Close(reason);
  }

  @override
  String get type => _type;

  @override
  void write(Packer msgPacker) {
    msgPacker
      ..packMapLength(2)
      ..packString(MessageFields.type)
      ..packString(_type)
      ..packString(MessageFields.reason)
      ..packInt(reason.toInt());
  }
}
