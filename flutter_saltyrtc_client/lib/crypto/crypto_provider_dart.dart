import 'dart:typed_data';

import 'package:dart_saltyrtc_client/dart_saltyrtc_client.dart';
import 'package:libsodium/libsodium.dart' as dart;

Crypto? _instance;

Future initCrypto() async {}

Crypto get cryptoInstance {
  _instance ??= _DartSodiumCrypto();

  return _instance!;
}

class _DartSodiumSharedKeyStore implements SharedKeyStore {
  @override
  final Uint8List sharedKey;

  _DartSodiumSharedKeyStore({
    required Uint8List ownPrivateKey,
    required Uint8List remotePublicKey,
  }) : sharedKey = dart.CryptoBox.sharedSecret(remotePublicKey, ownPrivateKey);
}

class DartSodiumKeyStore extends KeyStore {
  @override
  final Uint8List publicKey;
  @override
  final Uint8List privateKey;

  DartSodiumKeyStore({required this.publicKey, required this.privateKey});
}

class _DartSodiumCrypto extends Crypto {
  _DartSodiumCrypto() {
    dart.Sodium.init();
  }

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
    return _DartSodiumSharedKeyStore(
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

  @override
  Uint8List randomBytes(int size) {
    return dart.RandomBytes.buffer(size);
  }
}
