import 'dart:typed_data';

import 'package:dart_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;

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
  static const privateKeyBytes = 32;
  static const boxOverhead = 16;
  static const symmKeyBytes = 32;
  static const nonceBytes = Nonce.totalLength;

  Uint8List randomBytes(int size);

  KeyStore createRandomKeyStore();

  KeyStore createKeyStore(
      {required Uint8List privateKey, required Uint8List publicKey});

  Uint8List createRandomNonce();

  SharedKeyStore createSharedKeyStore(
      {required KeyStore ownKeyStore, required Uint8List remotePublicKey});
}
