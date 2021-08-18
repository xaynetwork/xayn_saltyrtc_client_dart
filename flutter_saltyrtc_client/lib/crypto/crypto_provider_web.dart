import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/dart_saltyrtc_client.dart'
    show SharedKeyStore, KeyStore, AuthToken, Crypto;
import 'package:flutter_saltyrtc_client/crypto/load_sodiumjs.dart'
    show loadSodiumInBrowser;
import 'package:flutter_saltyrtc_client/crypto/sodium.js.dart' show LibSodiumJS;

Future initCrypto() async {
  _sodiumJS = await loadSodiumInBrowser();
}

Crypto? _instance;
late LibSodiumJS _sodiumJS;

Crypto get cryptoInstance {
  _instance ??= _JSCrypto(_sodiumJS);

  return _instance!;
}

class _JSSharedKeyStore extends SharedKeyStore {
  final LibSodiumJS _sodium;
  final Uint8List _sharedKey;

  _JSSharedKeyStore({
    required LibSodiumJS sodium,
    required Uint8List ownPrivateKey,
    required Uint8List remotePublicKey,
  })  : _sodium = sodium,
        _sharedKey = sodium.crypto_box_beforenm(remotePublicKey, ownPrivateKey),
        super(ownPrivateKey: ownPrivateKey, remotePublicKey: remotePublicKey);

  @override
  Uint8List decrypt({
    required Uint8List ciphertext,
    required Uint8List nonce,
  }) {
    Crypto.checkNonce(nonce);
    return _sodium.crypto_box_open_easy_afternm(ciphertext, nonce, _sharedKey);
  }

  @override
  Uint8List encrypt({
    required Uint8List message,
    required Uint8List nonce,
  }) {
    Crypto.checkNonce(nonce);
    return _sodium.crypto_box_easy_afternm(message, nonce, _sharedKey);
  }
}

class _JSAuthToken implements AuthToken {
  final LibSodiumJS _sodium;
  final Uint8List _authToken;

  _JSAuthToken({
    required LibSodiumJS sodium,
    required Uint8List authToken,
  })  : _sodium = sodium,
        _authToken = authToken {
    Crypto.checkSymmetricKey(_authToken);
  }

  @override
  Uint8List decrypt({
    required Uint8List ciphertext,
    required Uint8List nonce,
  }) {
    Crypto.checkNonce(nonce);
    return _sodium.crypto_secretbox_open_easy(ciphertext, nonce, _authToken);
  }

  @override
  Uint8List encrypt({
    required Uint8List message,
    required Uint8List nonce,
  }) {
    Crypto.checkNonce(nonce);
    return _sodium.crypto_secretbox_easy(message, nonce, _authToken);
  }
}

class _JSCrypto extends Crypto {
  final LibSodiumJS _sodium;

  _JSCrypto(this._sodium);

  @override
  Uint8List randomBytes(int size) {
    return _sodium.randombytes_buf(size);
  }

  @override
  KeyStore createKeyStore() {
    final keyPair = _sodium.crypto_box_keypair();
    return KeyStore(
        privateKey: keyPair.privateKey, publicKey: keyPair.publicKey);
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
    return _JSSharedKeyStore(
      sodium: _sodium,
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
    return _JSAuthToken(sodium: _sodium, authToken: token);
  }
}
