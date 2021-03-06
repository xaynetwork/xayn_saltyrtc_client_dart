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

import 'dart:typed_data' show Uint8List;

import 'package:messagepack/messagepack.dart' show Unpacker;
import 'package:xayn_saltyrtc_client/src/crypto/crypto.dart'
    show CryptoBox, DecryptionFailedException;
import 'package:xayn_saltyrtc_client/src/logger.dart' show logger;
import 'package:xayn_saltyrtc_client/src/messages/c2c/application.dart'
    show Application;
import 'package:xayn_saltyrtc_client/src/messages/c2c/auth_initiator.dart'
    show AuthInitiator;
import 'package:xayn_saltyrtc_client/src/messages/c2c/auth_responder.dart'
    show AuthResponder;
import 'package:xayn_saltyrtc_client/src/messages/c2c/close.dart' show Close;
import 'package:xayn_saltyrtc_client/src/messages/c2c/key.dart' show Key;
import 'package:xayn_saltyrtc_client/src/messages/c2c/task_message.dart'
    show TaskMessage;
import 'package:xayn_saltyrtc_client/src/messages/c2c/token.dart' show Token;
import 'package:xayn_saltyrtc_client/src/messages/close_code.dart'
    show CloseCode;
import 'package:xayn_saltyrtc_client/src/messages/message.dart'
    show Message, MessageFields, MessageType;
import 'package:xayn_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;
import 'package:xayn_saltyrtc_client/src/messages/s2c/client_auth.dart'
    show ClientAuth;
import 'package:xayn_saltyrtc_client/src/messages/s2c/client_hello.dart'
    show ClientHello;
import 'package:xayn_saltyrtc_client/src/messages/s2c/disconnected.dart'
    show Disconnected;
import 'package:xayn_saltyrtc_client/src/messages/s2c/drop_responder.dart'
    show DropResponder;
import 'package:xayn_saltyrtc_client/src/messages/s2c/new_initiator.dart'
    show NewInitiator;
import 'package:xayn_saltyrtc_client/src/messages/s2c/new_responder.dart'
    show NewResponder;
import 'package:xayn_saltyrtc_client/src/messages/s2c/send_error.dart'
    show SendError;
import 'package:xayn_saltyrtc_client/src/messages/s2c/server_auth_initiator.dart'
    show ServerAuthInitiator;
import 'package:xayn_saltyrtc_client/src/messages/s2c/server_auth_responder.dart'
    show ServerAuthResponder;
import 'package:xayn_saltyrtc_client/src/messages/s2c/server_hello.dart'
    show ServerHello;
import 'package:xayn_saltyrtc_client/src/messages/validation.dart'
    show validateTypeType, validateStringMapType;
import 'package:xayn_saltyrtc_client/src/protocol/error.dart'
    show ProtocolErrorException, ValidationException;

extension MessageDecryptionExt on CryptoBox {
  /// Decrypts the message and reads it.
  ///
  /// If decryption fails `onDecryptionError` is called which can be used to
  /// do some logging/error handling and create the exception which will be
  /// throw. If `onDecryptionError` is not provided `ProtocolError` is used.
  ///
  Message readEncryptedMessage({
    required Uint8List msgBytes,
    required Nonce nonce,
    CloseCode? decryptionErrorCloseCode,
    List<String> taskTypes = const [],
  }) {
    final Uint8List decryptedBytes;
    try {
      decryptedBytes = decrypt(ciphertext: msgBytes, nonce: nonce.toBytes());
    } on DecryptionFailedException catch (e) {
      if (decryptionErrorCloseCode != null) {
        throw e.withCloseCode(decryptionErrorCloseCode);
      } else {
        rethrow;
      }
    }

    final msg = readMessage(decryptedBytes, taskTypes: taskTypes);
    return msg;
  }

  /// Decrypts the message, reads it and (checked) casts it.
  ///
  /// If decryption fails `onDecryptionError` is called which can be used to
  /// do some logging/error handling and create the exception which will be
  /// throw. If `onDecryptionError` is not provided `ProtocolError` is used.
  ///
  /// If the read message is not of the right dart type (A `is!` check) then
  /// a `ProtocolError` is thrown.
  T readEncryptedMessageOfType<T>({
    required Uint8List msgBytes,
    required Nonce nonce,
    required String msgType,
    CloseCode? decryptionErrorCloseCode,
  }) {
    final msg = readEncryptedMessage(
      msgBytes: msgBytes,
      nonce: nonce,
      decryptionErrorCloseCode: decryptionErrorCloseCode,
    );
    if (msg is! T) {
      throw ProtocolErrorException(
        'Unexpected message of type ${msg.type}, expected $msgType',
      );
    }
    return msg as T;
  }
}

/// Parse message from bytes. If the type is not one of types defined by the protocol
/// but is in `taskTypes` it will return `TaskMessage`.
/// It will throw an exception otherwise.
Message readMessage(Uint8List bytes, {List<String> taskTypes = const []}) {
  final msgUnpacker = Unpacker(bytes);
  final map = validateStringMapType(msgUnpacker.unpackMap(), 'message');
  final type = validateTypeType(map[MessageFields.type]);

  logger.d('Received $type');

  switch (type) {
    case MessageType.clientHello:
      return ClientHello.fromMap(map);
    case MessageType.serverHello:
      return ServerHello.fromMap(map);
    case MessageType.serverAuth:
      if (map.containsKey(MessageFields.initiatorConnected)) {
        return ServerAuthResponder.fromMap(map);
      } else if (map.containsKey(MessageFields.responders)) {
        return ServerAuthInitiator.fromMap(map);
      }
      throw const ValidationException(
        'Invalid ${MessageType.serverAuth} message',
      );
    case MessageType.clientAuth:
      return ClientAuth.fromMap(map);
    case MessageType.newInitiator:
      return NewInitiator.fromMap(map);
    case MessageType.newResponder:
      return NewResponder.fromMap(map);
    case MessageType.dropResponder:
      return DropResponder.fromMap(map);
    case MessageType.sendError:
      return SendError.fromMap(map);
    case MessageType.token:
      return Token.fromMap(map);
    case MessageType.key:
      return Key.fromMap(map);
    case MessageType.auth:
      if (map.containsKey(MessageFields.task)) {
        return AuthInitiator.fromMap(map);
      } else if (map.containsKey(MessageFields.tasks)) {
        return AuthResponder.fromMap(map);
      }
      throw const ValidationException(
        'Invalid ${MessageType.auth} message',
      );
    case MessageType.close:
      return Close.fromMap(map);
    case MessageType.application:
      return Application.fromMap(map);
    case MessageType.disconnected:
      return Disconnected.fromMap(map);
    default:
      if (taskTypes.contains(type)) {
        return TaskMessage.fromMap(map);
      }
  }

  throw ValidationException('Unknown message type: $type');
}
