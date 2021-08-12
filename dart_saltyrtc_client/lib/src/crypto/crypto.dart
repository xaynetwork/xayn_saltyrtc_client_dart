import 'dart:typed_data';

abstract class KeyStore {
  abstract final Uint8List publicKey;
  abstract final Uint8List privateKey;
}

abstract class SharedKeyStore {
  Uint8List encrypt({
    required Uint8List message,
    required Uint8List nonce,
  });

  Uint8List decrypt({
    required Uint8List ciphertext,
    required Uint8List nonce,
  });
}

abstract class Crypto {
  // specified by NaCl.
  static const publicKeyBytes = 32;
  static const boxOverhead = 16;
  static const symmKeyBytes = 32;

  Uint8List randomBytes(int size);

  KeyStore createRandomKeyStore();

  KeyStore createKeyStore(
      {required Uint8List privateKey, required Uint8List publicKey});

  Uint8List createRandomNonce();

  SharedKeyStore createSharedKeyStore(
      {required KeyStore ownKeyStore, required Uint8List remotePublicKey});
}
