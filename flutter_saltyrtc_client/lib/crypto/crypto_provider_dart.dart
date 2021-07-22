import 'dart:typed_data';

import 'package:dart_saltyrtc_client/dart_saltyrtc_client.dart';
import 'package:libsodium/libsodium.dart' as dart;

Crypto? _instance;

Future initCrypto() async {}

Crypto get cryptoInstance {
  _instance ??= _DartSodiumCrypto();

  return _instance!;
}

class DartSodiumSharedKeyStore implements SharedKeyStore {
  final Uint8List ownPrivateKey, remotePublicKey;

  DartSodiumSharedKeyStore({
    required this.ownPrivateKey,
    required this.remotePublicKey,
  }) {
    dart.Sodium.init();
  }

  Uint8List? _sharedKey;

  @override
  Uint8List get sharedKey => _sharedKey = _sharedKey ?? _createSharedKey();

  Uint8List _createSharedKey() {
    return dart.CryptoBox.sharedSecret(remotePublicKey, ownPrivateKey);
  }
}

class DartSodiumKeyStore extends KeyStore {
  @override
  final Uint8List publicKey;
  @override
  final Uint8List privateKey;

  DartSodiumKeyStore({required this.publicKey, required this.privateKey});
}

class _DartSodiumCrypto extends Crypto {
  @override
  KeyStore createRandomKeyStore() {
    final keyPair = dart.CryptoBox.randomKeys();
    return DartSodiumKeyStore(publicKey: keyPair.pk, privateKey: keyPair.sk);
  }

  @override
  Uint8List createRandomNonce() {
    return dart.CryptoBox.randomNonce();
  }

  @override
  Uint8List decrypt({
    required Uint8List ciphertext,
    required Uint8List nonce,
    required SharedKeyStore shared,
  }) {
    return dart.CryptoBox.decryptAfternm(ciphertext, nonce, shared.sharedKey);
  }

  @override
  Uint8List encrypt({
    required Uint8List message,
    required Uint8List nonce,
    required SharedKeyStore shared,
  }) {
    return dart.CryptoBox.encryptAfternm(message, nonce, shared.sharedKey);
  }

  @override
  SharedKeyStore createSharedKeyStore({
    required KeyStore ownKeyStore,
    required Uint8List remotePublicKey,
  }) {
    return DartSodiumSharedKeyStore(
      ownPrivateKey: (ownKeyStore as DartSodiumKeyStore).privateKey,
      remotePublicKey: remotePublicKey,
    );
  }

  @override
  KeyStore createKeyStore({
    required Uint8List publicKey,
    required Uint8List privateKey,
  }) {
    return DartSodiumKeyStore(publicKey: publicKey, privateKey: privateKey);
  }
}
