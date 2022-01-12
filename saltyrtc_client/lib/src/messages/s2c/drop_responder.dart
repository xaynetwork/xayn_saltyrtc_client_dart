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
import 'package:xayn_saltyrtc_client/src/messages/id.dart' show ResponderId, Id;
import 'package:xayn_saltyrtc_client/src/messages/message.dart'
    show Message, MessageType, MessageFields;
import 'package:xayn_saltyrtc_client/src/messages/validation.dart'
    show validateType, validateCloseCodeType, validateIntegerType;

const _type = MessageType.dropResponder;

@immutable
class DropResponder extends Message {
  final ResponderId id;
  final CloseCode? reason;

  @override
  List<Object?> get props => [id, reason];

  DropResponder(this.id, this.reason);

  factory DropResponder.fromMap(Map<String, Object?> map) {
    validateType(map[MessageFields.type], _type);

    final id = Id.responderId(
      validateIntegerType(map[MessageFields.id], MessageFields.id),
    );
    final reasonValue = map[MessageFields.reason];
    final reason = reasonValue == null
        ? null
        : validateCloseCodeType(reasonValue, true, MessageFields.reason);

    return DropResponder(id, reason);
  }

  @override
  String get type => _type;

  @override
  void write(Packer msgPacker) {
    final hasReason = reason != null;
    msgPacker
      ..packMapLength(hasReason ? 3 : 2)
      ..packString(MessageFields.type)
      ..packString(_type)
      ..packString(MessageFields.id)
      ..packInt(id.value);

    if (hasReason) {
      msgPacker
        ..packString(MessageFields.reason)
        ..packInt(reason!.toInt());
    }
  }
}
