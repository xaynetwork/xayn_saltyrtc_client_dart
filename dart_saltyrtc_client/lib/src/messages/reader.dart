import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/src/crypto/crypto.dart'
    show CryptoBox, DecryptionFailedException;
import 'package:dart_saltyrtc_client/src/logger.dart' show logger;
import 'package:dart_saltyrtc_client/src/messages/c2c/application.dart'
    show Application;
import 'package:dart_saltyrtc_client/src/messages/c2c/auth_initiator.dart'
    show AuthInitiator;
import 'package:dart_saltyrtc_client/src/messages/c2c/auth_responder.dart'
    show AuthResponder;
import 'package:dart_saltyrtc_client/src/messages/c2c/close.dart' show Close;
import 'package:dart_saltyrtc_client/src/messages/c2c/key.dart' show Key;
import 'package:dart_saltyrtc_client/src/messages/c2c/task_message.dart'
    show TaskMessage;
import 'package:dart_saltyrtc_client/src/messages/c2c/token.dart' show Token;
import 'package:dart_saltyrtc_client/src/messages/close_code.dart'
    show CloseCode;
import 'package:dart_saltyrtc_client/src/messages/message.dart'
    show Message, MessageFields, MessageType;
import 'package:dart_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;
import 'package:dart_saltyrtc_client/src/messages/s2c/client_auth.dart'
    show ClientAuth;
import 'package:dart_saltyrtc_client/src/messages/s2c/client_hello.dart'
    show ClientHello;
import 'package:dart_saltyrtc_client/src/messages/s2c/disconnected.dart'
    show Disconnected;
import 'package:dart_saltyrtc_client/src/messages/s2c/drop_responder.dart'
    show DropResponder;
import 'package:dart_saltyrtc_client/src/messages/s2c/new_initiator.dart'
    show NewInitiator;
import 'package:dart_saltyrtc_client/src/messages/s2c/new_responder.dart'
    show NewResponder;
import 'package:dart_saltyrtc_client/src/messages/s2c/send_error.dart'
    show SendError;
import 'package:dart_saltyrtc_client/src/messages/s2c/server_auth_initiator.dart'
    show ServerAuthInitiator;
import 'package:dart_saltyrtc_client/src/messages/s2c/server_auth_responder.dart'
    show ServerAuthResponder;
import 'package:dart_saltyrtc_client/src/messages/s2c/server_hello.dart'
    show ServerHello;
import 'package:dart_saltyrtc_client/src/messages/validation.dart'
    show validateTypeType, validateStringMapType;
import 'package:dart_saltyrtc_client/src/protocol/error.dart'
    show ProtocolException, ValidationException;
import 'package:messagepack/messagepack.dart' show Unpacker;

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

    final msg = readMessage(decryptedBytes);
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
      throw ProtocolException(
          'Unexpected message of type ${msg.type}, expected $msgType');
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
      throw ValidationException('Invalid ${MessageType.serverAuth} message');
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
      throw ValidationException('Invalid ${MessageType.auth} message');
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
