import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/dart_saltyrtc_client.dart'
    show SharedKeyStore, KeyStore, AuthToken, Crypto;
import 'package:libsodium/libsodium.dart' as _sodium;

Crypto? _instance;

Future initCrypto() async {}

Crypto get cryptoInstance {
  _instance ??= _DartSodiumCrypto();

  return _instance!;
}

class _DartSodiumSharedKeyStore extends SharedKeyStore {
  final Uint8List _sharedKey;

  _DartSodiumSharedKeyStore({
    required Uint8List ownPrivateKey,
    required Uint8List remotePublicKey,
  })  : _sharedKey =
            _sodium.CryptoBox.sharedSecret(remotePublicKey, ownPrivateKey),
        super(ownPrivateKey: ownPrivateKey, remotePublicKey: remotePublicKey);

  @override
  Uint8List decrypt({
    required Uint8List ciphertext,
    required Uint8List nonce,
  }) {
    Crypto.checkNonce(nonce);
    return _sodium.CryptoBox.decryptAfternm(ciphertext, nonce, _sharedKey);
  }

  @override
  Uint8List encrypt({
    required Uint8List message,
    required Uint8List nonce,
  }) {
    Crypto.checkNonce(nonce);
    return _sodium.CryptoBox.encryptAfternm(message, nonce, _sharedKey);
  }
}

class _DartSodiumAuthToken implements AuthToken {
  final Uint8List _authToken;

  _DartSodiumAuthToken(this._authToken) {
    Crypto.checkSymmetricKey(_authToken);
  }

  @override
  Uint8List decrypt({
    required Uint8List ciphertext,
    required Uint8List nonce,
  }) {
    Crypto.checkNonce(nonce);
    return _sodium.Sodium.cryptoSecretboxOpenEasy(
        ciphertext, nonce, _authToken);
  }

  @override
  Uint8List encrypt({
    required Uint8List message,
    required Uint8List nonce,
  }) {
    Crypto.checkNonce(nonce);
    return _sodium.Sodium.cryptoSecretboxEasy(message, nonce, _authToken);
  }
}

class _DartSodiumCrypto extends Crypto {
  _DartSodiumCrypto() {
    _sodium.Sodium.init();
  }

  @override
  Uint8List randomBytes(int size) {
    return _sodium.RandomBytes.buffer(size);
  }

  @override
  KeyStore createKeyStore() {
    final keyPair = _sodium.CryptoBox.randomKeys();
    return KeyStore(publicKey: keyPair.pk, privateKey: keyPair.sk);
  }

  @override
  KeyStore createKeyStoreFromKeys({
    required Uint8List publicKey,
    required Uint8List privateKey,
  }) {
    return KeyStore(publicKey: publicKey, privateKey: privateKey);
  }

  @override
  SharedKeyStore createSharedKeyStore({
    required KeyStore ownKeyStore,
    required Uint8List remotePublicKey,
  }) {
    return _DartSodiumSharedKeyStore(
      ownPrivateKey: ownKeyStore.privateKey,
      remotePublicKey: remotePublicKey,
    );
  }

  @override
  AuthToken createAuthToken() {
    return createAuthTokenFromToken(token: randomBytes(Crypto.symmKeyBytes));
  }

  @override
  AuthToken createAuthTokenFromToken({required Uint8List token}) {
    return _DartSodiumAuthToken(token);
  }
}
