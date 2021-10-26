import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/dart_saltyrtc_client.dart' show Crypto;
import 'package:flutter_saltyrtc_client/src/crypto/crypto_provider.dart'
    show getCrypto;
import 'package:test/test.dart';

import 'protocol.dart' show EncryptedMessage, KeyExchangeMessage;

extension CreateRandomNonce on Crypto {
  Uint8List createRandomNonce() {
    return randomBytes(Crypto.nonceBytes);
  }
}

// This test can fail on platforms that don't have libsodium installed, install libsodium before running it.
void main() async {
  final ping = Uint8List(4);
  final pong = Uint8List(8);

  test('Test the N key exchange variant with sodium.', () async {
    var crypto = await getCrypto();
    // Server generates keypair for it self
    final serverKeys = crypto.createKeyStore();

    final remotePublicKey = serverKeys.publicKey;

    // Client generates keypair for it self
    final clientKeys = crypto.createKeyStore();

    // Client precomputes shared key for server communication, this helps with performance
    final sharedSecretClient = crypto.createSharedKeyStore(
        ownKeyStore: clientKeys, remotePublicKey: remotePublicKey);

    // Client sends its public key encrypted to the server via signal server etc
    // The nonce is necessary to avoid that two same messages don't create the same encrypted bytes
    var nonce = crypto.createRandomNonce();

    // Note we are sending the public key encrypted with the server pk to the client, so we can verify that the client really used the PK of the server
    final msgToServerKeyExchange = KeyExchangeMessage(
      cipher: sharedSecretClient.encrypt(
          message: clientKeys.publicKey, nonce: nonce),
      nonce: nonce,
      pk: clientKeys.publicKey,
    );

    // Server will precompute a shared secret
    final sharedSecretServer = crypto.createSharedKeyStore(
        ownKeyStore: serverKeys, remotePublicKey: msgToServerKeyExchange.pk);

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
        nonce: nonce);

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
        nonce: nonce);

    // The server receives the pong
    final pongMessage = sharedSecretServer.decrypt(
      ciphertext: msgToServerPong.cipher,
      nonce: msgToServerPong.nonce,
    );
    expect(pongMessage, pong);
  });
}
