import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/dart_saltyrtc_client.dart'
    show SharedKeyStore, KeyStore, AuthToken, Crypto, DecryptionFailedException;
import 'package:libsodium/libsodium.dart' as _sodium;

Crypto? _instance;

Future<void> initCrypto() async {}

Crypto get cryptoInstance {
  _instance ??= _DartSodiumCrypto();

  return _instance!;
}

T _wrapDecryptionFailure<T>(T Function() code) {
  try {
    return code();
  } on _sodium.SodiumException catch (cause) {
    throw DecryptionFailedException(cause);
  }
}

class _DartSodiumKeyStore extends KeyStore {
  _DartSodiumKeyStore(
      {required Uint8List publicKey, required Uint8List privateKey})
      : super(publicKey: publicKey, privateKey: privateKey);

  @override
  Uint8List decrypt({
    required Uint8List remotePublicKey,
    required Uint8List ciphertext,
    required Uint8List nonce,
  }) {
    final sks = _DartSodiumSharedKeyStore(
        ownPrivateKey: privateKey, remotePublicKey: remotePublicKey);
    return sks.decrypt(ciphertext: ciphertext, nonce: nonce);
  }
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
    return _wrapDecryptionFailure(
        () => _sodium.CryptoBox.decryptAfternm(ciphertext, nonce, _sharedKey));
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
  @override
  final Uint8List bytes;

  _DartSodiumAuthToken(this.bytes) {
    Crypto.checkSymmetricKey(bytes);
  }

  @override
  Uint8List decrypt({
    required Uint8List ciphertext,
    required Uint8List nonce,
  }) {
    Crypto.checkNonce(nonce);
    return _wrapDecryptionFailure(
        () => _sodium.Sodium.cryptoSecretboxOpenEasy(ciphertext, nonce, bytes));
  }

  @override
  Uint8List encrypt({
    required Uint8List message,
    required Uint8List nonce,
  }) {
    Crypto.checkNonce(nonce);
    return _sodium.Sodium.cryptoSecretboxEasy(message, nonce, bytes);
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
    return _DartSodiumKeyStore(publicKey: keyPair.pk, privateKey: keyPair.sk);
  }

  @override
  KeyStore createKeyStoreFromKeys({
    required Uint8List publicKey,
    required Uint8List privateKey,
  }) {
    return _DartSodiumKeyStore(publicKey: publicKey, privateKey: privateKey);
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
