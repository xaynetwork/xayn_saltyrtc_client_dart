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
    show Message, MessageType, MessageFields;
import 'package:xayn_saltyrtc_client/src/messages/nonce/cookie.dart'
    show Cookie;
import 'package:xayn_saltyrtc_client/src/messages/validation.dart'
    show
        validateType,
        validateByteArrayType,
        validateByteArray,
        validateListType,
        validateIntegerType,
        validateInteger;

const _type = MessageType.clientAuth;

@immutable
class ClientAuth extends Message {
  final Cookie yourCookie;
  final Uint8List? yourKey;
  final List<String> subprotocols;
  final int pingInterval;

  @override
  List<Object?> get props => [yourCookie, yourKey, subprotocols, pingInterval];

  ClientAuth(
    this.yourCookie,
    this.yourKey,
    this.subprotocols,
    this.pingInterval,
  ) {
    const yourKeyLength = 32;
    validateInteger(pingInterval, 0, 1 << 31, MessageFields.pingInterval);

    if (yourKey != null) {
      validateByteArray(yourKey!, yourKeyLength, MessageFields.yourKey);
    }
  }

  factory ClientAuth.fromMap(Map<String, Object?> map) {
    validateType(map[MessageFields.type], _type);
    final yourCookie = Cookie(
      validateByteArrayType(
        map[MessageFields.yourCookie],
        MessageFields.yourCookie,
      ),
    );
    final subprotocols = validateListType<String>(
      map[MessageFields.subprotocols],
      MessageFields.subprotocols,
    );
    final pingInterval = validateIntegerType(
      map[MessageFields.pingInterval],
      MessageFields.pingInterval,
    );

    final yourKeyValue = map[MessageFields.yourKey];
    final yourKey = yourKeyValue == null
        ? null
        : validateByteArrayType(yourKeyValue, MessageFields.yourKey);

    return ClientAuth(yourCookie, yourKey, subprotocols, pingInterval);
  }

  @override
  String get type => _type;

  @override
  void write(Packer msgPacker) {
    final hasKey = yourKey != null;
    msgPacker
      ..packMapLength(hasKey ? 5 : 4)
      ..packString(MessageFields.type)
      ..packString(_type)
      ..packString(MessageFields.yourCookie)
      ..packBinary(yourCookie.toBytes())
      ..packString(MessageFields.pingInterval)
      ..packInt(pingInterval);
    if (hasKey) {
      msgPacker
        ..packString(MessageFields.yourKey)
        ..packBinary(yourKey);
    }

    msgPacker
      ..packString(MessageFields.subprotocols)
      ..packListLength(subprotocols.length);
    for (final subprotocol in subprotocols) {
      msgPacker.packString(subprotocol);
    }
  }
}
