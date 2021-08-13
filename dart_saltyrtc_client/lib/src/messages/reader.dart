import 'dart:typed_data' show Uint8List;

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
import 'package:dart_saltyrtc_client/src/messages/message.dart'
    show Message, MessageFields, MessageType;
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
    show ValidationError, validateTypeType, validateStringMapType;
import 'package:messagepack/messagepack.dart' show Unpacker;

/// Parse message from bytes. If the type is not one of types defined by the protocol
/// but is in `taskTypes` it will return `TaskMessage`.
/// It will throw an exception otherwise.
Message readMessage(Uint8List bytes, [List<String> taskTypes = const []]) {
  final msgUnpacker = Unpacker(bytes);
  final map = validateStringMapType(msgUnpacker.unpackMap(), 'message');
  final type = validateTypeType(map[MessageFields.type]);

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
      throw ValidationError('Invalid ${MessageType.serverAuth} message');
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
      throw ValidationError('Invalid ${MessageType.auth} message');
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

  throw ValidationError('Unknown message type: $type');
}
