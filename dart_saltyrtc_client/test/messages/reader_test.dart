import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/src/crypto/crypto.dart' show Crypto;
import 'package:dart_saltyrtc_client/src/messages/c2c/application.dart'
    show Application;
import 'package:dart_saltyrtc_client/src/messages/c2c/auth_initiator.dart'
    show AuthInitiator;
import 'package:dart_saltyrtc_client/src/messages/c2c/auth_responder.dart'
    show AuthResponder;
import 'package:dart_saltyrtc_client/src/messages/c2c/close.dart' show Close;
import 'package:dart_saltyrtc_client/src/messages/c2c/key.dart' show Key;
import 'package:dart_saltyrtc_client/src/messages/c2c/token.dart' show Token;
import 'package:dart_saltyrtc_client/src/messages/close_code.dart'
    show CloseCode;
import 'package:dart_saltyrtc_client/src/messages/message.dart'
    show signedKeysLength;
import 'package:dart_saltyrtc_client/src/messages/message.dart' show Message;
import 'package:dart_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;
import 'package:dart_saltyrtc_client/src/messages/reader.dart' show readMessage;
import 'package:dart_saltyrtc_client/src/messages/s2c/client_auth.dart'
    show ClientAuth;
import 'package:dart_saltyrtc_client/src/messages/s2c/client_hello.dart'
    show ClientHello;
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
import 'package:test/test.dart';

void checkRead<T extends Message>(T Function() getMsg) {
  final msg = getMsg();
  expect(readMessage(msg.toBytes()), allOf(isA<T>(), msg));
}

void main() {
  final key = Uint8List(Crypto.publicKeyBytes);
  final signedKeys = Uint8List(signedKeysLength);
  final yourCookie = Uint8List(Nonce.cookieLength);
  final taskData = {
    'task': {
      'task_data': [1, 2, 3]
    }
  };

  test('Read server hello', () {
    checkRead(() => ServerHello(key));
  });

  test('Read client hello', () {
    checkRead(() => ClientHello(key));
  });

  test('Read server auth initiator', () {
    checkRead(() => ServerAuthInitiator(yourCookie, signedKeys, [2]));
  });

  test('Read server auth responder', () {
    checkRead(() => ServerAuthResponder(yourCookie, signedKeys, true));
  });

  test('Read client auth', () {
    checkRead(() => ClientAuth(yourCookie, key, ['custom.proto'], 60));
  });

  test('Read client auth', () {
    checkRead(() => ClientAuth(yourCookie, key, ['custom.proto'], 60));
  });

  test('Read new initiator', () {
    checkRead(() => NewInitiator());
  });

  test('Read new responder', () {
    checkRead(() => NewResponder(2));
  });

  test('Read drop responder', () {
    checkRead(() => DropResponder(2, CloseCode.protocolError));
  });

  test('Read send error', () {
    checkRead(() => SendError(Uint8List(SendError.idLength)));
  });

  test('Read token', () {
    checkRead(() => Token(key));
  });

  test('Read key', () {
    checkRead(() => Key(key));
  });

  test('Read auth initiator', () {
    checkRead(() => AuthInitiator(yourCookie, 'task', taskData));
  });

  test('Read auth responder', () {
    checkRead(() => AuthResponder(yourCookie, ['task'], taskData));
  });

  test('Read close', () {
    checkRead(() => Close(CloseCode.closingNormal));
  });

  test('Read application', () {
    checkRead(() => Application(Uint8List(10)));
  });
}
