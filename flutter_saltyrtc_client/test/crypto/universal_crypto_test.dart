import 'dart:typed_data' show Uint8List;

import 'package:test/test.dart';
import 'package:xayn_flutter_saltyrtc_client/crypto.dart'
    show getCrypto, Crypto, SecretStreamTag;

import 'protocol.dart' show EncryptedMessage, KeyExchangeMessage;

extension CreateRandomNonce on Crypto {
  Uint8List createRandomNonce() {
    return randomBytes(Crypto.nonceBytes);
  }
}

// This test can fail on platforms that don't have libsodium installed, install libsodium before running it.
Future<void> main() async {
  final ping = Uint8List(4);
  final pong = Uint8List(8);

  test('Test the N key exchange variant with sodium.', () async {
    final crypto = await getCrypto();
    // Server generates keypair for it self
    final serverKeys = crypto.createKeyStore();

    final remotePublicKey = serverKeys.publicKey;

    // Client generates keypair for it self
    final clientKeys = crypto.createKeyStore();

    // Client precomputes shared key for server communication, this helps with performance
    final sharedSecretClient = crypto.createSharedKeyStore(
      ownKeyStore: clientKeys,
      remotePublicKey: remotePublicKey,
    );

    // Client sends its public key encrypted to the server via signal server etc
    // The nonce is necessary to avoid that two same messages don't create the same encrypted bytes
    var nonce = crypto.createRandomNonce();

    // Note we are sending the public key encrypted with the server pk to the client, so we can verify that the client really used the PK of the server
    final msgToServerKeyExchange = KeyExchangeMessage(
      cipher: sharedSecretClient.encrypt(
        message: clientKeys.publicKey,
        nonce: nonce,
      ),
      nonce: nonce,
      pk: clientKeys.publicKey,
    );

    // Server will precompute a shared secret
    final sharedSecretServer = crypto.createSharedKeyStore(
      ownKeyStore: serverKeys,
      remotePublicKey: msgToServerKeyExchange.pk,
    );

    // Server received the message and will now decrypt it
    final publicKeyClient = sharedSecretServer.decrypt(
      ciphertext: msgToServerKeyExchange.cipher,
      nonce: msgToServerKeyExchange.nonce,
    );
    expect(publicKeyClient, msgToServerKeyExchange.pk);

    // Now the server and client are holding public keys and can now send each other messages
    nonce = crypto.createRandomNonce();
    final msgToClientPing = EncryptedMessage(
      cipher: sharedSecretServer.encrypt(
        message: ping,
        nonce: nonce,
      ),
      nonce: nonce,
    );

    // The client receives the ping, decrypts it and sends back a pong
    final pingMessage = sharedSecretClient.decrypt(
      ciphertext: msgToClientPing.cipher,
      nonce: msgToClientPing.nonce,
    );
    expect(pingMessage, ping);

    // The client sends back a pong message
    nonce = crypto.createRandomNonce();
    final msgToServerPong = EncryptedMessage(
      cipher: sharedSecretClient.encrypt(
        message: pong,
        nonce: nonce,
      ),
      nonce: nonce,
    );

    // The server receives the pong
    final pongMessage = sharedSecretServer.decrypt(
      ciphertext: msgToServerPong.cipher,
      nonce: msgToServerPong.nonce,
    );
    expect(pongMessage, pong);
  });

  group('test secret stream', () {
    test('normal message sending', () async {
      final msg1 = Uint8List.fromList([1, 2, 4, 8, 16, 32]);
      final msg2 = Uint8List.fromList([1, 3, 9, 27]);
      final msg3 = Uint8List.fromList([33, 44, 55, 12]);
      final msg4 = Uint8List.fromList([]);
      final msg5 = Uint8List.fromList([4, 8, 12]);

      final crypto = await getCrypto();

      final ssbOfA =
          crypto.createKXSecretStreamBuilder(onePeerTrueOneFalse: true);
      final ssbOfB =
          crypto.createKXSecretStreamBuilder(onePeerTrueOneFalse: false);
      final ssOfA = ssbOfA.build(ssbOfB.publicKey);
      final ssOfB = ssbOfB.build(ssbOfA.publicKey);

      var tmp = ssOfB.decryptPackage(ssOfA.encryptPackage(msg1));
      expect(tmp.message, equals(msg1));
      tmp = ssOfB.decryptPackage(ssOfA.encryptPackage(msg2));
      expect(tmp.message, equals(msg2));
      tmp = ssOfA.decryptPackage(ssOfB.encryptPackage(msg3));
      expect(tmp.message, equals(msg3));
      tmp = ssOfA.decryptPackage(ssOfB.encryptPackage(msg4));
      expect(tmp.message, equals(msg4));
      tmp = ssOfA.decryptPackage(ssOfB.encryptPackage(msg5));
      expect(tmp.message, equals(msg5));
    });

    test('just one half used', () async {
      final msg1 = Uint8List.fromList([1, 2, 4, 8, 16, 32]);
      final msg2 = Uint8List.fromList([1, 3, 9, 27]);
      final msg3 = Uint8List.fromList([33, 44, 55, 12]);
      final msg4 = Uint8List.fromList([]);

      final crypto = await getCrypto();

      final ssbOfA =
          crypto.createKXSecretStreamBuilder(onePeerTrueOneFalse: true);
      final ssbOfB =
          crypto.createKXSecretStreamBuilder(onePeerTrueOneFalse: false);
      final ssOfA = ssbOfA.build(ssbOfB.publicKey);
      final ssOfB = ssbOfB.build(ssbOfA.publicKey);

      var tmp = ssOfB.decryptPackage(ssOfA.encryptPackage(msg1));
      expect(tmp.message, equals(msg1));
      tmp = ssOfB.decryptPackage(ssOfA.encryptPackage(msg2));
      expect(tmp.message, equals(msg2));
      tmp = ssOfB.decryptPackage(ssOfA.encryptPackage(msg3));
      expect(tmp.message, equals(msg3));
      tmp = ssOfB.decryptPackage(ssOfA.encryptPackage(msg4));
      expect(tmp.message, equals(msg4));
    });

    test('sending tags', () async {
      final msg1 = Uint8List.fromList([1, 2, 4, 8, 16, 32]);
      final msg2 = Uint8List.fromList([1, 3, 9, 27]);
      final msg3 = Uint8List.fromList([33, 44, 55, 12]);
      final msg4 = Uint8List.fromList([]);

      final crypto = await getCrypto();

      final ssbOfA =
          crypto.createKXSecretStreamBuilder(onePeerTrueOneFalse: true);
      final ssbOfB =
          crypto.createKXSecretStreamBuilder(onePeerTrueOneFalse: false);
      final ssOfA = ssbOfA.build(ssbOfB.publicKey);
      final ssOfB = ssbOfB.build(ssbOfA.publicKey);

      var tmp = ssOfA.decryptPackage(
        ssOfB.encryptPackage(msg1, tag: SecretStreamTag.push),
      );
      expect(tmp.message, equals(msg1));
      expect(tmp.tag, equals(SecretStreamTag.push));

      expect(ssOfA.isDecryptionClosed, isFalse);
      expect(ssOfA.isEncryptionClosed, isFalse);
      expect(ssOfB.isDecryptionClosed, isFalse);
      expect(ssOfB.isEncryptionClosed, isFalse);

      tmp = ssOfA.decryptPackage(
        ssOfB.encryptPackage(msg2, tag: SecretStreamTag.rekey),
      );
      expect(tmp.message, equals(msg2));
      expect(tmp.tag, equals(SecretStreamTag.rekey));

      expect(ssOfA.isDecryptionClosed, isFalse);
      expect(ssOfA.isEncryptionClosed, isFalse);
      expect(ssOfB.isDecryptionClosed, isFalse);
      expect(ssOfB.isEncryptionClosed, isFalse);

      tmp = ssOfA.decryptPackage(
        ssOfB.encryptPackage(msg2, tag: SecretStreamTag.message),
      );
      expect(tmp.message, equals(msg2));
      expect(tmp.tag, equals(SecretStreamTag.message));

      expect(ssOfA.isDecryptionClosed, isFalse);
      expect(ssOfA.isEncryptionClosed, isFalse);
      expect(ssOfB.isDecryptionClosed, isFalse);
      expect(ssOfB.isEncryptionClosed, isFalse);

      tmp = ssOfA.decryptPackage(
        ssOfB.encryptPackage(msg3, tag: SecretStreamTag.push),
      );
      expect(tmp.message, equals(msg3));
      expect(tmp.tag, equals(SecretStreamTag.push));

      expect(ssOfA.isDecryptionClosed, isFalse);
      expect(ssOfA.isEncryptionClosed, isFalse);
      expect(ssOfB.isDecryptionClosed, isFalse);
      expect(ssOfB.isEncryptionClosed, isFalse);

      tmp = ssOfA.decryptPackage(
        ssOfB.encryptPackage(msg3, tag: SecretStreamTag.finalMessage),
      );
      expect(tmp.message, equals(msg3));
      expect(tmp.tag, equals(SecretStreamTag.finalMessage));

      expect(ssOfA.isDecryptionClosed, isTrue);
      expect(ssOfA.isEncryptionClosed, isFalse);
      expect(ssOfB.isDecryptionClosed, isFalse);
      expect(ssOfB.isEncryptionClosed, isTrue);

      tmp = ssOfB.decryptPackage(
        ssOfA.encryptPackage(msg4, tag: SecretStreamTag.finalMessage),
      );
      expect(tmp.message, equals(msg4));
      expect(tmp.tag, equals(SecretStreamTag.finalMessage));
    });
  });
}
