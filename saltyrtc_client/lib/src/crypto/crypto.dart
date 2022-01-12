// Copyright 2021 Xayn AG
//
// Licensed under the Apache License, Version 2.0 (the License);
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:typed_data' show Uint8List;

import 'package:meta/meta.dart' show immutable, protected;
import 'package:xayn_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;
import 'package:xayn_saltyrtc_client/src/protocol/error.dart'
    show ProtocolErrorException;

/// Exception we map provider specific decryption failure exceptions to.
///
/// Decryption failure is a special case of an protocol error,
/// in some edge cases we catch decryption failure and handle it differently.
@immutable
class DecryptionFailedException extends ProtocolErrorException {
  const DecryptionFailedException(Object cause)
      : super('decryption failed: $cause');
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

/// Abstraction over various NaCL specific crypto methods.
abstract class Crypto {
  // specified by NaCl.
  static const publicKeyBytes = 32;
  static const privateKeyBytes = 32;
  static const boxOverhead = 16;
  static const symmKeyBytes = 32;
  static const nonceBytes = Nonce.totalLength;
  static const secretStreamHeaderBytes = 24;

  Uint8List randomBytes(int size);

  KeyStore createKeyStore();

  KeyStore createKeyStoreFromKeys({
    required Uint8List privateKey,
    required Uint8List publicKey,
  });

  SharedKeyStore createSharedKeyStore({
    required KeyStore ownKeyStore,
    required Uint8List remotePublicKey,
  });

  AuthToken createAuthToken();

  AuthToken createAuthTokenFromToken({required Uint8List token});

  /// Create a builder for building a SecretStream using a key exchange.
  ///
  /// The `onePeerTrueOneFalse` must bee `true` for one peer and `false`
  /// for the other, this is needed to decide which peer uses the first key
  /// for the receiver channel and which uses it for the transmitter channel.
  KXSecretStreamBuilder createKXSecretStreamBuilder({
    required bool onePeerTrueOneFalse,
  });

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

  static void checkSecretStreamHeader(Uint8List header) {
    _checkLength(
      header,
      Crypto.secretStreamHeaderBytes,
      'secret stream header',
    );
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
        'Expects either an authToken OR a trustedResponderSharedKey',
      );
    }
  }

  /// Create an instance from either an `AuthToken` or the public key
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
          'crypto & initiatorPermanentPublicKey required for trusted responder',
        );
      }
      trustedResponderSharedKey = createResponderSharedPermanentKey(
        crypto,
        initiatorPermanentKeys,
        trustedResponderPermanentPublicKey,
      );
    }

    return InitialClientAuthMethod._(
      authToken: authToken,
      trustedResponderSharedKey: trustedResponderSharedKey,
    );
  }

  static SharedKeyStore createResponderSharedPermanentKey(
    Crypto crypto,
    KeyStore initiatorPermanentKeys,
    Uint8List trustedResponderPublicPermanentKey,
  ) {
    Crypto.checkPublicKey(trustedResponderPublicPermanentKey);
    return crypto.createSharedKeyStore(
      ownKeyStore: initiatorPermanentKeys,
      remotePublicKey: trustedResponderPublicPermanentKey,
    );
  }
}

/// A builder for a [SecretStream] by using a key exchange.
abstract class KXSecretStreamBuilder {
  /// This public key needs to be "safely" transmitted to the peer.
  ///
  /// This could be done by using a existing end-to-end encrypted signaling
  /// channel. While the public key doesn't need to be sent through such a channel
  /// it's the easiest way as it mean you don't have to take various precautions
  /// to avoid MITM attacks, replay attacks and similar.
  Uint8List get publicKey;

  /// Setup the stream based on the peers public key and our key pair.
  ///
  /// # SecretStream Header
  ///
  /// As this API doesn't provide a way to exchange a header during setup,
  /// the only possible implementation is to attach the header to the
  /// first exchanged message.
  ///
  /// This is secure, to quote the documentation of libsodium:
  ///
  /// >  The header content doesn't have to be secret and decryption with
  ///    a different header would fail.
  ///
  SecretStream build(Uint8List peerPublicKey);
}

/// A tag which can be used to:
///
/// - close the stream
/// - signal the end of a group
/// - rekey the encryption
///
enum SecretStreamTag {
  /// Default, equivalent to setting no tag.
  message,

  /// If used the stream will treat it as last message and "close".
  finalMessage,

  /// Marks the end of a set of messages (but not the end of the stream).
  ///
  /// This can be useful to implement chunking.
  push,

  /// Deterministically create a new key and forget the old key.
  ///
  /// The message itself is still encrypted with the old key.
  ///
  /// The new key is deterministically created on both sides based on the
  /// current nonce, key and sequence number (all internal). This can be
  /// used to archive forward security, but crypto expertise
  /// is recommended to properly determine weather or not the given behavior
  /// is good enough for your use case.
  rekey,
}

abstract class SecretStream {
  /// Encrypt the given package returning the encrypted data.
  ///
  /// The encrypted package then needs to be send to the peer.
  ///
  /// If additional data is given the data also needs to be provided to
  /// the decryption function or the message authentication will fail (it
  /// uses AEAD).
  ///
  /// If the tag is set to [SecretStreamTag.finalMessage] then it will close
  /// the encryption after encrypting the message and will cause the peer
  /// decryption to be closed after it decrypts the message containing the tag.
  ///
  /// Trying to encrypt packages when the encryption part was already closed
  /// will throw an exception.
  Uint8List encryptPackage(
    Uint8List raw, {
    Uint8List? additionalData,
    SecretStreamTag tag = SecretStreamTag.message,
  });

  /// Decrypts the given package returning the decrypted data and tag.
  ///
  /// If additional data was provided when encrypting the package the exact
  /// same additional data needs to be provided when when decrypting it or
  /// the message authentication will fail (it uses AEAD).
  ///
  /// If the received tag is [SecretStreamTag.finalMessage] then the
  /// decryption is now closed.
  ///
  /// Trying to decrypt packages when the decryption part was already closed
  /// will throw an exception.
  SecretStreamDecryptionResult decryptPackage(
    Uint8List encrypted, {
    Uint8List? additionalData,
  });

  bool get isEncryptionClosed;
  bool get isDecryptionClosed;

  @protected
  static int tagToInt(SecretStreamTag tag) {
    switch (tag) {
      case SecretStreamTag.message:
        return 0;
      case SecretStreamTag.push:
        return 1;
      case SecretStreamTag.rekey:
        return 2;
      case SecretStreamTag.finalMessage:
        return 3;
    }
  }

  @protected
  static SecretStreamTag intToTag(int tag) {
    switch (tag) {
      case 0:
        return SecretStreamTag.message;
      case 1:
        return SecretStreamTag.push;
      case 2:
        return SecretStreamTag.rekey;
      case 3:
        return SecretStreamTag.finalMessage;
      default:
        throw ArgumentError('expected only tag 0-3');
    }
  }
}

class SecretStreamDecryptionResult {
  final Uint8List message;
  final SecretStreamTag tag;

  SecretStreamDecryptionResult(this.message, this.tag);
}

class SecretStreamClosedException implements Exception {
  final bool _incoming;

  SecretStreamClosedException({required bool incoming}) : _incoming = incoming;

  @override
  String toString() {
    return 'SecretStreamClose: The ${_incoming ? 'incoming' : 'outgoing'} part already received a `final` tag';
  }
}
