import 'dart:typed_data' show Uint8List;

import 'package:test/test.dart';
import 'package:xayn_saltyrtc_client/src/crypto/crypto.dart' show Crypto;
import 'package:xayn_saltyrtc_client/src/messages/c2c/application.dart'
    show Application;
import 'package:xayn_saltyrtc_client/src/messages/c2c/auth_initiator.dart'
    show AuthInitiator;
import 'package:xayn_saltyrtc_client/src/messages/c2c/auth_responder.dart'
    show AuthResponder;
import 'package:xayn_saltyrtc_client/src/messages/c2c/close.dart' show Close;
import 'package:xayn_saltyrtc_client/src/messages/c2c/key.dart' show Key;
import 'package:xayn_saltyrtc_client/src/messages/c2c/token.dart' show Token;
import 'package:xayn_saltyrtc_client/src/messages/close_code.dart'
    show CloseCode;
import 'package:xayn_saltyrtc_client/src/messages/id.dart' show Id;
import 'package:xayn_saltyrtc_client/src/messages/message.dart'
    show MessageType, signedKeysLength;
import 'package:xayn_saltyrtc_client/src/messages/message.dart' show Message;
import 'package:xayn_saltyrtc_client/src/messages/nonce/cookie.dart'
    show Cookie;
import 'package:xayn_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;
import 'package:xayn_saltyrtc_client/src/messages/reader.dart'
    show MessageDecryptionExt, readMessage;
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
import 'package:xayn_saltyrtc_client/src/protocol/peer.dart' show Responder;

import '../crypto_mock.dart' show crypto;
import '../utils.dart'
    show setUpTesting, throwsProtocolError, throwsValidationError;

void checkRead<T extends Message>(T Function() getMsg) {
  final msg = getMsg();
  expect(readMessage(msg.toBytes()), allOf(isA<T>(), msg));
}

void main() {
  setUpTesting();

  group('readMessage', () {
    final key = Uint8List(Crypto.publicKeyBytes);
    final signedKeys = Uint8List(signedKeysLength);
    final yourCookie = Cookie(Uint8List(Cookie.cookieLength));
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
      checkRead(
        () => ServerAuthInitiator(yourCookie, signedKeys, [Id.responderId(2)]),
      );
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
      checkRead(() => NewResponder(Id.responderId(2)));
    });

    test('Read drop responder', () {
      checkRead(
        () => DropResponder(Id.responderId(2), CloseCode.protocolError),
      );
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

    test('Missing entry in task data is error, not null', () {
      expect(
        () {
          AuthResponder(yourCookie, ['task'], {});
        },
        throwsValidationError(),
      );
      //but null is ok
      AuthResponder(yourCookie, ['task'], {'task': null});
    });

    test('Read close', () {
      checkRead(() => Close(CloseCode.closingNormal));
    });

    test('Read application', () {
      checkRead(() => Application(Uint8List(10)));
    });
  });

  group('MessageDecryptionExt', () {
    final keyFrom = crypto.createKeyStore();
    final keyTo = crypto.createKeyStore();
    final receiver = Responder(Id.responderId(12), crypto);
    final sharedKey = crypto.createSharedKeyStore(
      ownKeyStore: keyTo,
      remotePublicKey: keyFrom.publicKey,
    );
    receiver.setSessionSharedKey(sharedKey);
    final message = Close(CloseCode.noSharedTask);
    final nonce = Nonce.fromRandom(
      source: Id.initiatorAddress,
      destination: receiver.id,
      randomBytes: crypto.randomBytes,
    );
    final encryptedMessage = receiver.encrypt(message, nonce);

    group('readEncryptedMessage', () {
      test('decrypts and reads the message', () {
        final msg = sharedKey.readEncryptedMessage(
          msgBytes: encryptedMessage,
          nonce: nonce,
        );
        expect(msg, equals(message));
      });

      test('throws a protocol error if decryption fails', () {
        expect(
          () {
            sharedKey.readEncryptedMessage(
              msgBytes: Uint8List(Nonce.totalLength + 10),
              nonce: nonce,
            );
          },
          throwsProtocolError(),
        );
      });

      test('allows setting custom c2c close code', () {
        expect(
          () {
            sharedKey.readEncryptedMessage(
              msgBytes: Uint8List(Nonce.totalLength + 10),
              nonce: nonce,
              decryptionErrorCloseCode: CloseCode.handover,
            );
          },
          throwsProtocolError(closeCode: CloseCode.handover),
        );
      });
    });
    group('readEncryptedMessageOfType', () {
      // Test expected readEncryptedMessage to be used internally and
      // hence doesn't test the decryption.
      test('casts the type', () {
        final msg = sharedKey.readEncryptedMessageOfType<Close>(
          msgBytes: encryptedMessage,
          nonce: nonce,
          msgType: MessageType.close,
        );
        expect(msg, equals(message));
        expect(msg, isA<Close>());
      });

      test('throws a ProtocolError if the type mismatches', () {
        expect(
          () {
            sharedKey.readEncryptedMessageOfType<Disconnected>(
              msgBytes: encryptedMessage,
              nonce: nonce,
              msgType: MessageType.disconnected,
            );
          },
          throwsProtocolError(),
        );
      });
    });
  });
}
