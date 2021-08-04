import 'dart:convert';
import 'dart:typed_data';

const Utf8Codec utf8 = Utf8Codec();

abstract class KeyStore {
  abstract final Uint8List publicKey;
  abstract final Uint8List privateKey;
}

abstract class SharedKeyStore {
  abstract final Uint8List sharedKey;
}

abstract class Crypto {
  Uint8List encrypt({
    required Uint8List message,
    required Uint8List nonce,
    required SharedKeyStore shared,
  });

  Uint8List encryptString({
    required String message,
    required Uint8List nonce,
    required SharedKeyStore shared,
  }) =>
      encrypt(
          message: utf8.encoder.convert(message), nonce: nonce, shared: shared);

  Uint8List decrypt({
    required Uint8List ciphertext,
    required Uint8List nonce,
    required SharedKeyStore shared,
  });

  String decryptString({
    required Uint8List ciphertext,
    required Uint8List nonce,
    required SharedKeyStore shared,
  }) =>
      utf8.decoder.convert(
          decrypt(ciphertext: ciphertext, nonce: nonce, shared: shared));

  KeyStore createRandomKeyStore();

  KeyStore createKeyStore(
      {required Uint8List privateKey, required Uint8List publicKey});

  Uint8List createRandomNonce();

  SharedKeyStore createSharedKeyStore(
      {required KeyStore ownKeyStore, required Uint8List remotePublicKey});
}