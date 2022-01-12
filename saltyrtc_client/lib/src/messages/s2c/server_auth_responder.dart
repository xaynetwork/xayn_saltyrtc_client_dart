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
import 'package:xayn_saltyrtc_client/src/messages/message.dart'
    show Message, MessageType, MessageFields, signedKeysLength;
import 'package:xayn_saltyrtc_client/src/messages/nonce/cookie.dart'
    show Cookie;
import 'package:xayn_saltyrtc_client/src/messages/validation.dart'
    show
        validateType,
        validateByteArrayType,
        validateByteArray,
        validateBoolType,
        validateTypeWithNull;

const _type = MessageType.serverAuth;

@immutable
class ServerAuthResponder extends Message {
  final Cookie yourCookie;
  final Uint8List? signedKeys;
  final bool initiatorConnected;

  @override
  List<Object?> get props => [yourCookie, signedKeys, initiatorConnected];

  ServerAuthResponder(
    this.yourCookie,
    this.signedKeys,
    this.initiatorConnected,
  ) {
    if (signedKeys != null) {
      validateByteArray(
        signedKeys!,
        signedKeysLength,
        MessageFields.signedKeys,
      );
    }
  }

  factory ServerAuthResponder.fromMap(Map<String, Object?> map) {
    validateType(map[MessageFields.type], _type);
    final yourCookie = Cookie(
      validateByteArrayType(
        map[MessageFields.yourCookie],
        MessageFields.yourCookie,
      ),
    );
    final initatorConnected = validateBoolType(
      map[MessageFields.initiatorConnected],
      MessageFields.initiatorConnected,
    );

    final signedKeys = validateTypeWithNull(
      map[MessageFields.signedKeys],
      MessageFields.signedKeys,
      validateByteArrayType,
    );

    return ServerAuthResponder(yourCookie, signedKeys, initatorConnected);
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
      ..packBinary(yourCookie.toBytes())
      ..packString(MessageFields.initiatorConnected)
      ..packBool(initiatorConnected);

    if (hasKeys) {
      msgPacker
        ..packString(MessageFields.signedKeys)
        ..packBinary(signedKeys);
    }
  }
}
