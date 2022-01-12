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

import 'dart:typed_data' show Uint8List;

import 'package:messagepack/messagepack.dart' show Packer;
import 'package:meta/meta.dart' show immutable;
import 'package:xayn_saltyrtc_client/src/messages/id.dart' show Id, ResponderId;
import 'package:xayn_saltyrtc_client/src/messages/message.dart'
    show Message, MessageType, MessageFields, signedKeysLength;
import 'package:xayn_saltyrtc_client/src/messages/nonce/cookie.dart'
    show Cookie;
import 'package:xayn_saltyrtc_client/src/messages/validation.dart'
    show
        validateType,
        validateByteArrayType,
        validateByteArray,
        validateListType,
        validateTypeWithNull;
import 'package:xayn_saltyrtc_client/src/protocol/error.dart'
    show ValidationException;

const _type = MessageType.serverAuth;

@immutable
class ServerAuthInitiator extends Message {
  final Cookie yourCookie;
  final Uint8List? signedKeys;
  final List<ResponderId> responders;

  @override
  List<Object?> get props => [yourCookie, signedKeys, responders];

  ServerAuthInitiator(this.yourCookie, this.signedKeys, this.responders) {
    if (signedKeys != null) {
      validateByteArray(
        signedKeys!,
        signedKeysLength,
        MessageFields.signedKeys,
      );
    }
    if (responders.length != responders.toSet().length) {
      throw const ValidationException(
        '${MessageFields.responders} must not contain duplicates',
      );
    }
  }

  factory ServerAuthInitiator.fromMap(Map<String, Object?> map) {
    validateType(map[MessageFields.type], _type);
    final yourCookie = Cookie(
      validateByteArrayType(
        map[MessageFields.yourCookie],
        MessageFields.yourCookie,
      ),
    );
    final responders = validateListType<int>(
      map[MessageFields.responders],
      MessageFields.responders,
    ).map(Id.responderId).toList(growable: false);

    final signedKeys = validateTypeWithNull(
      map[MessageFields.signedKeys],
      MessageFields.signedKeys,
      validateByteArrayType,
    );

    return ServerAuthInitiator(yourCookie, signedKeys, responders);
  }

  @override
  String get type => _type;

  @override
  void write(Packer msgPacker) {
    final hasKeys = signedKeys != null;
    msgPacker
      ..packMapLength(hasKeys ? 4 : 3)
      ..packString(MessageFields.type)
      ..packString(_type)
      ..packString(MessageFields.yourCookie)
      ..packBinary(yourCookie.toBytes());

    if (hasKeys) {
      msgPacker
        ..packString(MessageFields.signedKeys)
        ..packBinary(signedKeys);
    }

    msgPacker
      ..packString(MessageFields.responders)
      ..packListLength(responders.length);
    for (final responder in responders) {
      msgPacker.packInt(responder.value);
    }
  }
}
