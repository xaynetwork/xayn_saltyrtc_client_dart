import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;
import 'package:dart_saltyrtc_client/src/protocol/error.dart'
    show ProtocolException;
import 'package:meta/meta.dart' show immutable;

/// Exception we map provider specific decryption failure exceptions to.
///
/// Decryption failure is a special case of an protocol error,
/// in some edge cases we catch decryption failure and handle it differently.
@immutable
class DecryptionFailedException extends ProtocolException {
  DecryptionFailedException(Object cause) : super('decryption failed: $cause');
}

/// Something that can encrypt and decrypt data.
abstract class CryptoBox {
  Uint8List encrypt({
    required Uint8List message,
    required Uint8List nonce,
  });

  Uint8List decrypt({
    required Uint8List ciphertext,
    required Uint8List nonce,
  });
}

/// Store the public and private asymmetric key of a peer.
abstract class KeyStore {
  final Uint8List publicKey;
  final Uint8List privateKey;

  KeyStore({required this.publicKey, required this.privateKey}) {
    Crypto.checkPublicKey(publicKey);
    Crypto.checkPrivateKey(privateKey);
  }
}

/// A `SharedKeyStore` holds the resulting precalculated shared key of
/// the local peer's secret key and the remote peer's public key.
abstract class SharedKeyStore implements CryptoBox {
  final Uint8List remotePublicKey;
  final Uint8List ownPrivateKey;

  SharedKeyStore({required this.ownPrivateKey, required this.remotePublicKey}) {
    Crypto.checkPrivateKey(ownPrivateKey);
    Crypto.checkPublicKey(remotePublicKey);
  }
}

/// Token that is used to authenticate a responder if it is not trusted
abstract class AuthToken implements CryptoBox {
  Uint8List get bytes;
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

@immutable
class InitialClientAuthMethod {
  /// A preset trusted responder shared permanent key.
  ///
  /// This key is a shared key based on the initiators permanent key and the
  /// responders permanent key.
  final SharedKeyStore? trustedResponderSharedKey;
  final AuthToken? authToken;

  InitialClientAuthMethod._({this.authToken, this.trustedResponderSharedKey}) {
    if ((trustedResponderSharedKey == null) == (authToken == null)) {
      throw ArgumentError(
          'Expects either a authToken OR a trustedResponderSharedKey');
    }
  }

  /// Create a instance from either an `AuthToken` or the public key
  /// of the trusted responder.
  ///
  /// The `crypto` and `initiatorPermanentKeys` are required if the trusted
  /// responders permanent public key is used.
  factory InitialClientAuthMethod.fromEither({
    AuthToken? authToken,
    Uint8List? trustedResponderPermanentPublicKey,
    Crypto? crypto,
    KeyStore? initiatorPermanentKeys,
  }) {
    SharedKeyStore? trustedResponderSharedKey;
    if (trustedResponderPermanentPublicKey != null) {
      if (crypto == null || initiatorPermanentKeys == null) {
        throw ArgumentError(
            'crypto & initiatorPermanentPublicKey required for trusted responder');
      }
      trustedResponderSharedKey = createResponderSharedPermanentKey(
          crypto, initiatorPermanentKeys, trustedResponderPermanentPublicKey);
    }

    return InitialClientAuthMethod._(
      authToken: authToken,
      trustedResponderSharedKey: trustedResponderSharedKey,
    );
  }

  static SharedKeyStore createResponderSharedPermanentKey(
      Crypto crypto,
      KeyStore initiatorPermanentKeys,
      Uint8List trustedResponderPublicPermanentKey) {
    Crypto.checkPublicKey(trustedResponderPublicPermanentKey);
    return crypto.createSharedKeyStore(
        ownKeyStore: initiatorPermanentKeys,
        remotePublicKey: trustedResponderPublicPermanentKey);
  }
}
