import 'package:libsodium/libsodium.dart';
import 'package:test/test.dart';

import 'protocol.dart';

// This test can fail on platforms that don't have libsodium installed, install libsodium before running it.
void main() async {
  test('Test the N key exchange variant with sodium.', () {
    // Server generates keypair for itself
    final serverKeys = CryptoBox.randomKeys();

    // Server sends public key to client, via QR code, sms, link, etc (unencrypted)
    final serverPublicKey = serverKeys.pk;

    // Client generates keypair for it self
    final clientKeys = CryptoBox.randomKeys();

    // Client precomputes shared key for server communication, this helps with performance
    final sharedSecretClient =
        CryptoBox.sharedSecret(serverPublicKey, clientKeys.sk);

    // Client sends its public key encrypted to the server via signal server etc
    // The nonce is necessary to avoid that two same messages don't create the same encrypted bytes
    var nonce = CryptoBox.randomNonce();

    // Note we are sending the public key encrypted with the server pk to the client, so we can verify that the client really used the PK of the server
    final msgToServerKeyExchange = KeyExchangeMessage(
      cipher:
          CryptoBox.encryptAfternm(clientKeys.pk, nonce, sharedSecretClient),
      nonce: nonce,
      pk: clientKeys.pk,
    );

    // Server will precompute a shared secret
    final sharedSecretServer =
        CryptoBox.sharedSecret(msgToServerKeyExchange.pk, serverKeys.sk);

    // Server received the message and will now decrypt it
    final publicKeyClient = CryptoBox.decryptAfternm(
        msgToServerKeyExchange.cipher,
        msgToServerKeyExchange.nonce,
        sharedSecretServer);
    expect(publicKeyClient, msgToServerKeyExchange.pk);

    // Now the server and client are holding public keys and can now send each other messages
    nonce = CryptoBox.randomNonce();
    final msgToClientPing = EncryptedMessage(
        cipher:
            CryptoBox.encryptStringAfternm('PING', nonce, sharedSecretServer),
        nonce: nonce);

    // The client receives the ping, decrypts it and sends back a pong
    final pingMessage = CryptoBox.decryptStringAfternm(
        msgToClientPing.cipher, msgToClientPing.nonce, sharedSecretClient);
    expect(pingMessage, 'PING');

    // The client sends back a pong message
    nonce = CryptoBox.randomNonce();
    final msgToServerPong = EncryptedMessage(
        cipher:
            CryptoBox.encryptStringAfternm('PONG', nonce, sharedSecretClient),
        nonce: nonce);

    // The server receives the pong
    final pongMessage = CryptoBox.decryptStringAfternm(
        msgToServerPong.cipher, msgToServerPong.nonce, sharedSecretServer);
    expect(pongMessage, 'PONG');
  });
}