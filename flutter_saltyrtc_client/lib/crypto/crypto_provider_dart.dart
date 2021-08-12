import 'dart:typed_data';

import 'package:dart_saltyrtc_client/dart_saltyrtc_client.dart'
    show SharedKeyStore, KeyStore, AuthToken, Crypto;
import 'package:flutter_saltyrtc_client/crypto/checks.dart'
    show checkNonce, checkPrivateKey, checkPublicKey;
import 'package:libsodium/libsodium.dart' as _sodium;

Crypto? _instance;

Future initCrypto() async {}

Crypto get cryptoInstance {
  _instance ??= _DartSodiumCrypto();

  return _instance!;
}

class _DartSodiumSharedKeyStore implements SharedKeyStore {
  final Uint8List _sharedKey;

  _DartSodiumSharedKeyStore({
    required Uint8List ownPrivateKey,
    required Uint8List remotePublicKey,
  }) : _sharedKey =
            _sodium.CryptoBox.sharedSecret(remotePublicKey, ownPrivateKey) {
    checkPublicKey(remotePublicKey);
    checkPrivateKey(ownPrivateKey);
  }

  @override
  Uint8List decrypt({
    required Uint8List ciphertext,
    required Uint8List nonce,
  }) {
    checkNonce(nonce);
    return _sodium.CryptoBox.decryptAfternm(ciphertext, nonce, _sharedKey);
  }

  @override
  Uint8List encrypt({
    required Uint8List message,
    required Uint8List nonce,
  }) {
    checkNonce(nonce);
    return _sodium.CryptoBox.encryptAfternm(message, nonce, _sharedKey);
  }
}

class _DartSodiumKeyStore extends KeyStore {
  @override
  final Uint8List publicKey;
  @override
  final Uint8List privateKey;

  _DartSodiumKeyStore({required this.publicKey, required this.privateKey}) {
    checkPublicKey(publicKey);
    checkPrivateKey(privateKey);
  }
}

class _DartSodiumCrypto extends Crypto {
  _DartSodiumCrypto() {
    _sodium.Sodium.init();
  }

  @override
  KeyStore createRandomKeyStore() {
    final keyPair = _sodium.CryptoBox.randomKeys();
    return _DartSodiumKeyStore(publicKey: keyPair.pk, privateKey: keyPair.sk);
  }

  @override
  Uint8List createRandomNonce() {
    return _sodium.CryptoBox.randomNonce();
  }

  @override
  SharedKeyStore createSharedKeyStore({
    required KeyStore ownKeyStore,
    required Uint8List remotePublicKey,
  }) {
    return _DartSodiumSharedKeyStore(
      ownPrivateKey: (ownKeyStore as _DartSodiumKeyStore).privateKey,
      remotePublicKey: remotePublicKey,
    );
  }

  @override
  KeyStore createKeyStore({
    required Uint8List publicKey,
    required Uint8List privateKey,
  }) {
    return _DartSodiumKeyStore(publicKey: publicKey, privateKey: privateKey);
  }

  @override
  Uint8List randomBytes(int size) {
    return _sodium.RandomBytes.buffer(size);
  }
}
