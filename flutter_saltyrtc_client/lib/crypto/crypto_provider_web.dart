import 'dart:typed_data';

import 'package:dart_saltyrtc_client/dart_saltyrtc_client.dart';
import 'package:flutter_saltyrtc_client/crypto/load_sodiumjs.dart';
import 'package:flutter_saltyrtc_client/crypto/sodium.js.dart';

Future initCrypto() async {
  _sodiumJS = await loadSodiumInBrowser();
}

Crypto? _instance;
late LibSodiumJS _sodiumJS;

Crypto get cryptoInstance {
  _instance ??= _JSCrypto(_sodiumJS);

  return _instance!;
}

class _JSKeyStore extends KeyStore {
  @override
  final Uint8List publicKey;

  @override
  final Uint8List privateKey;

  _JSKeyStore({required this.publicKey, required this.privateKey});

  factory _JSKeyStore.fromKeyPair(KeyPair keyPair) =>
      _JSKeyStore(privateKey: keyPair.privateKey, publicKey: keyPair.publicKey);
}

class _JSSharedKeyStore implements SharedKeyStore {
  final LibSodiumJS _sodium;
  final Uint8List _sharedKey;

  _JSSharedKeyStore({
    required LibSodiumJS sodium,
    required Uint8List ownPrivateKey,
    required Uint8List remotePublicKey,
  })  : _sodium = sodium,
        _sharedKey = sodium.crypto_box_beforenm(remotePublicKey, ownPrivateKey);

  @override
  Uint8List decrypt({
    required Uint8List ciphertext,
    required Uint8List nonce,
  }) {
    return _sodium.crypto_box_open_easy_afternm(ciphertext, nonce, _sharedKey);
  }

  @override
  Uint8List encrypt({
    required Uint8List message,
    required Uint8List nonce,
  }) {
    return _sodium.crypto_box_easy_afternm(message, nonce, _sharedKey);
  }
}

class _JSCrypto extends Crypto {
  final LibSodiumJS _sodium;

  _JSCrypto(this._sodium);

  @override
  KeyStore createRandomKeyStore() {
    return _JSKeyStore.fromKeyPair(_sodium.crypto_box_keypair());
  }

  @override
  Uint8List createRandomNonce() {
    return _sodium.randombytes_buf(_sodium.crypto_box_NONCEBYTES);
  }

  @override
  SharedKeyStore createSharedKeyStore({
    required KeyStore ownKeyStore,
    required Uint8List remotePublicKey,
  }) {
    return _JSSharedKeyStore(
      sodium: _sodium,
      ownPrivateKey: (ownKeyStore as _JSKeyStore).privateKey,
      remotePublicKey: remotePublicKey,
    );
  }

  @override
  KeyStore createKeyStore({
    required Uint8List publicKey,
    required Uint8List privateKey,
  }) {
    return _JSKeyStore(publicKey: publicKey, privateKey: privateKey);
  }

  @override
  Uint8List randomBytes(int size) {
    return _sodium.randombytes_buf(size);
  }
}
