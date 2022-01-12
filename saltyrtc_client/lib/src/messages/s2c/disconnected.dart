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
import 'package:xayn_saltyrtc_client/src/messages/id.dart' show ClientId, Id;
import 'package:xayn_saltyrtc_client/src/messages/message.dart'
    show Message, MessageType, MessageFields;
import 'package:xayn_saltyrtc_client/src/messages/validation.dart'
    show validateType, validateIntegerType;

const _type = MessageType.disconnected;

@immutable
class Disconnected extends Message {
  final ClientId id;

  @override
  List<Object> get props => [id];

  Disconnected(this.id);

  factory Disconnected.fromMap(Map<String, Object?> map) {
    validateType(map[MessageFields.type], _type);
    // An initiator should validate that the id is a responder.
    // A responder should validate the id to be 1.
    // Here we validate the rage 1 <= id <= 255.
    final id = Id.clientId(
      validateIntegerType(map[MessageFields.id], MessageFields.id),
    );

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
      ..packInt(id.value);
  }
}
