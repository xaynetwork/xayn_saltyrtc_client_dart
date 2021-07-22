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

class JSKeyStore extends KeyStore {
  @override
  final Uint8List publicKey;

  @override
  final Uint8List privateKey;

  JSKeyStore({required this.publicKey, required this.privateKey});

  factory JSKeyStore.fromKeyPair(KeyPair keyPair) =>
      JSKeyStore(privateKey: keyPair.privateKey, publicKey: keyPair.publicKey);
}

class JSSharedKeyStore implements SharedKeyStore {
  final Uint8List Function() createSharedKey;

  JSSharedKeyStore({
    required this.createSharedKey,
  });

  Uint8List? _sharedKey;

  @override
  Uint8List get sharedKey => _sharedKey = _sharedKey ?? createSharedKey();
}

class _JSCrypto extends Crypto {
  final LibSodiumJS _sodium;

  _JSCrypto(this._sodium);

  @override
  KeyStore createRandomKeyStore() {
    return JSKeyStore.fromKeyPair(_sodium.crypto_box_keypair());
  }

  @override
  Uint8List createRandomNonce() {
    return _sodium.randombytes_buf(_sodium.crypto_box_NONCEBYTES);
  }

  @override
  Uint8List decrypt({
    required Uint8List ciphertext,
    required Uint8List nonce,
    required SharedKeyStore shared,
  }) {
    return _sodium.crypto_box_open_easy_afternm(
        ciphertext, nonce, shared.sharedKey);
  }

  @override
  Uint8List encrypt({
    required Uint8List message,
    required Uint8List nonce,
    required SharedKeyStore shared,
  }) {
    return _sodium.crypto_box_easy_afternm(message, nonce, shared.sharedKey);
  }

  @override
  SharedKeyStore createSharedKeyStore({
    required KeyStore ownKeyStore,
    required Uint8List remotePublicKey,
  }) {
    return JSSharedKeyStore(
        createSharedKey: () => _sodium.crypto_box_beforenm(
            remotePublicKey, ownKeyStore.privateKey));
  }

  @override
  KeyStore createKeyStore({
    required Uint8List publicKey,
    required Uint8List privateKey,
  }) {
    return JSKeyStore(publicKey: publicKey, privateKey: privateKey);
  }
}
