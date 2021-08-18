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

abstract class AuthToken {
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

  KeyStore createKeyStore();

  KeyStore createKeyStoreFromKeys(
      {required Uint8List privateKey, required Uint8List publicKey});

  SharedKeyStore createSharedKeyStore(
      {required KeyStore ownKeyStore, required Uint8List remotePublicKey});

  AuthToken createAuthToken();

  AuthToken createAuthTokenFromToken({required Uint8List token});

  static void checkNonce(Uint8List nonce) {
    _checkLength(nonce, Crypto.nonceBytes, 'nonce');
  }

  static void checkPublicKey(Uint8List publicKey) {
    _checkLength(publicKey, Crypto.publicKeyBytes, 'public key');
  }

  static void checkPrivateKey(Uint8List privateKey) {
    _checkLength(privateKey, Crypto.privateKeyBytes, 'private key');
  }

  static void checkSymmetricKey(Uint8List symmKey) {
    _checkLength(symmKey, Crypto.symmKeyBytes, 'symmetric key');
  }
}

void _checkLength(Uint8List data, int expected, String name) {
  final len = data.length;
  if (len != expected) {
    throw ArgumentError('$name must be $expected, found $len');
  }
}
