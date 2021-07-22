import 'dart:convert';

import 'package:dart_saltyrtc_client/dart_saltyrtc_client.dart';
import 'package:flutter_saltyrtc_client/crypto/crypto_provider.dart';
import 'package:test/test.dart';

import 'protocol.dart';

// This test can fail on platforms that don't have libsodium installed, install libsodium before running it.
void main() async {
  test('Test the N key exchange variant with sodium.', () async {
    await CryptoProvider.init();
    var crypto = CryptoProvider.instance;
    // Server geerates keypair for it self
    final serverKeys = crypto.createRandomKeyStore();

    final remotePublicKey = serverKeys.publicKey;

    // Client generates keypair for it self
    final clientKeys = crypto.createRandomKeyStore();

    // Client precomputes shared key for server communication, this helps with performance
    final sharedSecretClient = crypto.createSharedKeyStore(
        ownKeyStore: clientKeys, remotePublicKey: remotePublicKey);

    // Client sends its public key encrypted to the server via signal server etc
    // The nonce is necessary to avoid that two same messages don't create the same encrypted bytes
    var nonce = crypto.createRandomNonce();

    // Note we are sending the public key encrypted with the server pk to the client, so we can verify that the client really used the PK of the server
    final msgToServerKeyExchange = KeyExchangeMessage(
      cipher: crypto.encrypt(
          message: clientKeys.publicKey,
          nonce: nonce,
          shared: sharedSecretClient),
      nonce: nonce,
      pk: clientKeys.publicKey,
    );

    // Server will precompute a shared secret
    final sharedSecretServer = crypto.createSharedKeyStore(
        ownKeyStore: serverKeys, remotePublicKey: msgToServerKeyExchange.pk);

    // Server received the message and will now decrypt it
    final publicKeyClient = crypto.decrypt(
        ciphertext: msgToServerKeyExchange.cipher,
        nonce: msgToServerKeyExchange.nonce,
        shared: sharedSecretServer);
    expect(publicKeyClient, msgToServerKeyExchange.pk);

    // Now the server and client are holding public keys and can now send each other messages
    nonce = crypto.createRandomNonce();
    final msgToClientPing = EncryptedMessage(
        cipher: crypto.encryptString(
          message: 'PING',
          nonce: nonce,
          shared: sharedSecretServer,
        ),
        nonce: nonce);

    // The client receives the ping, decrypts it and sends back a pong
    final pingMessage = crypto.decryptString(
        ciphertext: msgToClientPing.cipher,
        nonce: msgToClientPing.nonce,
        shared: sharedSecretClient);
    expect(pingMessage, 'PING');

    // The client sends back a pong message
    nonce = crypto.createRandomNonce();
    final msgToServerPong = EncryptedMessage(
        cipher: crypto.encryptString(
          message: 'PONG',
          nonce: nonce,
          shared: sharedSecretClient,
        ),
        nonce: nonce);

    // The server receives the pong
    final pongMessage = crypto.decryptString(
        ciphertext: msgToServerPong.cipher,
        nonce: msgToServerPong.nonce,
        shared: sharedSecretServer);
    expect(pongMessage, 'PONG');
  });

  test('Test that serialized messages are recreated correctly', () async {
    await CryptoProvider.init();
    final crypto = CryptoProvider.instance;

    // Server restores keypair for it self
    final serverKeys = crypto.fromString(
        'F88QPyiyqHd5jRsiayuLFEJA1UObnpr8woiy0Q/2Q0s=;A6eXNGnD27XLzwCHDyrzd15YwQ2D6/TaPAmlfWEQqf8=');

    final remotePublicKey = serverKeys.publicKey;

    // Client restores keypair for it self
    final clientKeys = crypto.fromString(
        'hzVk5Ir3nDtVmOSc7kOLuJ7AiKfjc3eLjXBnmEe7ajY=;xVTDIJXRrM1NWUSa3uih9zyIfvAC2mGVvrqDi/CL37k=');

    // Client precomputes shared key for server communication, this helps with performance
    final sharedSecretClient = crypto.createSharedKeyStore(
        ownKeyStore: clientKeys, remotePublicKey: remotePublicKey);

    // Client sends its public key encrypted to the server via signal server etc
    // The nonce is necessary to avoid that two same messages don't create the same encrypted bytes
    var nonce = base64.decode('qZJAiu2CfxIkQaAKqqT2GSjNc8Zxoe/e');

    // Note we are sending the public key encrypted with the server pk to the client, so we can verify that the client really used the PK of the server
    final msgToServerKeyExchange = KeyExchangeMessage(
      cipher: crypto.encrypt(
          message: clientKeys.publicKey,
          nonce: nonce,
          shared: sharedSecretClient),
      nonce: nonce,
      pk: clientKeys.publicKey,
    );
    expect(msgToServerKeyExchange.toString(),
        '{"type":"keyExchange","data":{"message":"bAadUa13Lr5yV4NIKmrD+PT6lhjj0pxI7eh0jFuwNi6eU9vgxp1IoTNHo/8RQ+zh","nonce":"qZJAiu2CfxIkQaAKqqT2GSjNc8Zxoe/e","pk":"hzVk5Ir3nDtVmOSc7kOLuJ7AiKfjc3eLjXBnmEe7ajY="},"version":1}');

    // Server will precompute a shared secret
    final sharedSecretServer = crypto.createSharedKeyStore(
        ownKeyStore: serverKeys, remotePublicKey: msgToServerKeyExchange.pk);

    // Server received the message and will now decrypt it
    final publicKeyClient = crypto.decrypt(
        ciphertext: msgToServerKeyExchange.cipher,
        nonce: msgToServerKeyExchange.nonce,
        shared: sharedSecretServer);
    expect(publicKeyClient, msgToServerKeyExchange.pk);

    // Now the server and client are holding public keys and can now send each other messages
    nonce = base64.decode('NgGl2MO2zuZDUMPwjtv1AsrKev8+NE3C');
    final msgToClientPing = EncryptedMessage(
        cipher: crypto.encryptString(
          message: 'PING',
          nonce: nonce,
          shared: sharedSecretServer,
        ),
        nonce: nonce);

    expect(msgToClientPing.toString(),
        '{"type":"encrypted","data":{"message":"QUeYPajRVkq53V2s81NNv13eHR8=","nonce":"NgGl2MO2zuZDUMPwjtv1AsrKev8+NE3C"},"version":1}');

    // The client receives the ping, decrypts it and sends back a pong
    final pingMessage = crypto.decryptString(
        ciphertext: msgToClientPing.cipher,
        nonce: msgToClientPing.nonce,
        shared: sharedSecretClient);
    expect(pingMessage, 'PING');

    // The client sends back a pong message
    nonce = base64.decode('hAQMRNZ4sP2JPNZ5HP01UssA6GsajJ2C');
    final msgToServerPong = EncryptedMessage(
        cipher: crypto.encryptString(
          message: 'PONG',
          nonce: nonce,
          shared: sharedSecretClient,
        ),
        nonce: nonce);
    expect(msgToServerPong.toString(),
        '{"type":"encrypted","data":{"message":"bT603wr15RyWe27ZH96GwuZwiNY=","nonce":"hAQMRNZ4sP2JPNZ5HP01UssA6GsajJ2C"},"version":1}');

    // The server receives the pong
    final pongMessage = crypto.decryptString(
        ciphertext: msgToServerPong.cipher,
        nonce: msgToServerPong.nonce,
        shared: sharedSecretServer);
    expect(pongMessage, 'PONG');
  });
}

extension _CryptoExtension on Crypto {
  KeyStore fromString(String keys) {
    final split = keys.split(';');

    return createKeyStore(
        privateKey: base64.decode(split[1]),
        publicKey: base64.decode(split[0]));
  }
}
