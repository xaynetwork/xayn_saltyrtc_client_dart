import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/dart_saltyrtc_client.dart';
import 'package:dart_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;

/// Store the public and private asymmetric key of a peer.
abstract class KeyStore {
  final Uint8List publicKey;
  final Uint8List privateKey;

  KeyStore({required this.publicKey, required this.privateKey}) {
    Crypto.checkPublicKey(publicKey);
    Crypto.checkPrivateKey(privateKey);
  }

  Uint8List decrypt({
    required Uint8List remotePublicKey,
    required Uint8List ciphertext,
    required Uint8List nonce,
  });
}

/// A `SharedKeyStore` holds the resulting precalculated shared key of
/// the local peer's secret key and the remote peer's public key.
abstract class SharedKeyStore {
  final Uint8List remotePublicKey;
  final Uint8List ownPrivateKey;

  SharedKeyStore({required this.ownPrivateKey, required this.remotePublicKey}) {
    Crypto.checkPrivateKey(ownPrivateKey);
    Crypto.checkPublicKey(remotePublicKey);
  }

  Uint8List encrypt({
    required Uint8List message,
    required Uint8List nonce,
  });

  Uint8List decrypt({
    required Uint8List ciphertext,
    required Uint8List nonce,
  });
}

/// Token that is used to authenticate a responder if it is not trusted
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
