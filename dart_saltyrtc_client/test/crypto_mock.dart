import 'dart:math' show Random;
import 'dart:typed_data' show BytesBuilder, Uint8List;

import 'package:collection/collection.dart' show ListEquality;
import 'package:dart_saltyrtc_client/src/crypto/crypto.dart'
    show SharedKeyStore, Crypto, AuthToken, KeyStore;

final listEq = ListEquality<int>();

class _MockKeyStore extends KeyStore {
  _MockKeyStore({required Uint8List publicKey, required Uint8List privateKey})
      : super(publicKey: publicKey, privateKey: privateKey);

  @override
  Uint8List decrypt(
      {required Uint8List remotePublicKey,
      required Uint8List ciphertext,
      required Uint8List nonce}) {
    final sks = _MockSharedKeyStore(
        ownPrivateKey: privateKey, remotePublicKey: remotePublicKey);
    return sks.decrypt(ciphertext: ciphertext, nonce: nonce);
  }
}

class _MockSharedKeyStore extends SharedKeyStore {
  _MockSharedKeyStore({
    required Uint8List ownPrivateKey,
    required Uint8List remotePublicKey,
  }) : super(ownPrivateKey: ownPrivateKey, remotePublicKey: remotePublicKey);

  @override
  Uint8List decrypt({
    required Uint8List ciphertext,
    required Uint8List nonce,
  }) {
    return decryptWith(ciphertext: ciphertext, nonce: nonce);
  }

  @override
  Uint8List encrypt({
    required Uint8List message,
    required Uint8List nonce,
  }) {
    return encryptWith(message: message, nonce: nonce, key: remotePublicKey);
  }
}

class _MockAuthToken extends AuthToken {
  final Uint8List _token;

  _MockAuthToken(this._token);

  @override
  Uint8List decrypt({
    required Uint8List ciphertext,
    required Uint8List nonce,
  }) {
    return decryptWith(ciphertext: ciphertext, nonce: nonce);
  }

  @override
  Uint8List encrypt({required Uint8List message, required Uint8List nonce}) {
    return encryptWith(message: message, nonce: nonce, key: _token);
  }
}

Uint8List encryptWith({
  required Uint8List message,
  required Uint8List nonce,
  required Uint8List key,
}) {
  final bytes = BytesBuilder(copy: false);
  bytes
    ..add(nonce)
    // we add the key to avoid that this could be read as a valid message
    // and as a way to check, were possible, that the correct key was used.
    // we can only use Crypto.boxOverhead bytes
    ..add(Uint8List.sublistView(key, 0, Crypto.boxOverhead))
    ..add(message);
  return bytes.takeBytes();
}

Uint8List decryptWith({
  required Uint8List ciphertext,
  required Uint8List nonce,
}) {
  Crypto.checkNonce(nonce);
  // we skip the partial key
  return Uint8List.sublistView(ciphertext, Crypto.boxOverhead);
}

class MockCrypto extends Crypto {
  final _random = Random();

  @override
  AuthToken createAuthToken() {
    return _MockAuthToken(randomBytes(Crypto.symmKeyBytes));
  }

  @override
  AuthToken createAuthTokenFromToken({required Uint8List token}) {
    return _MockAuthToken(token);
  }

  @override
  KeyStore createKeyStore() {
    return _MockKeyStore(
      publicKey: randomBytes(Crypto.publicKeyBytes),
      privateKey: randomBytes(Crypto.privateKeyBytes),
    );
  }

  @override
  KeyStore createKeyStoreFromKeys(
      {required Uint8List privateKey, required Uint8List publicKey}) {
    return _MockKeyStore(publicKey: publicKey, privateKey: privateKey);
  }

  @override
  SharedKeyStore createSharedKeyStore(
      {required KeyStore ownKeyStore, required Uint8List remotePublicKey}) {
    return _MockSharedKeyStore(
      ownPrivateKey: ownKeyStore.privateKey,
      remotePublicKey: remotePublicKey,
    );
  }

  @override
  Uint8List randomBytes(int size) {
    return Uint8List.fromList(List.generate(size, (_) => _random.nextInt(255)));
  }
}
