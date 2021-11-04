import 'dart:ffi';
import 'dart:typed_data' show BytesBuilder, Uint8List;

import 'package:dart_saltyrtc_client/crypto.dart'
    show
        AuthToken,
        Crypto,
        DecryptionFailedException,
        KXSecretStreamBuilder,
        KeyStore,
        SecretStream,
        SecretStreamClosedException,
        SecretStreamTag,
        SharedKeyStore;
import 'package:flutter_saltyrtc_client/crypto.dart';
import 'package:libsodium/libsodium.dart' as _sodium;

Future<Crypto> loadCrypto() async {
  return _DartSodiumCrypto();
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

  @override
  KXSecretStreamBuilder createKXSecretStreamBuilder({
    required bool onePeerTrueOneFalse,
  }) =>
      _KXSecretStreamBuilder(
        _sodium.Sodium.cryptoKxKeypair(),
        onePeerTrueOneFalse,
      );
}

class _KXSecretStreamBuilder extends KXSecretStreamBuilder {
  final _sodium.KeyPair keyPair;
  final bool onePeerTrueOneFalse;

  @override
  Uint8List get publicKey => keyPair.pk;

  _KXSecretStreamBuilder(this.keyPair, this.onePeerTrueOneFalse);

  @override
  _SecretStream build(Uint8List peerPublicKey) {
    final mkKeys = onePeerTrueOneFalse
        ? _sodium.Sodium.cryptoKxServerSessionKeys
        : _sodium.Sodium.cryptoKxClientSessionKeys;
    final sessionKeys = mkKeys(keyPair.pk, keyPair.sk, peerPublicKey);
    final initPushResult =
        _sodium.Sodium.cryptoSecretstreamXchacha20poly1305InitPush(
            sessionKeys.tx);
    final stream = _SecretStream._(
      encryptionState: initPushResult.state,
      encryptionHeader: initPushResult.header,
      decryptionKey: sessionKeys.rx,
    );
    return stream;
  }
}

class _SecretStream extends SecretStream {
  Pointer<Uint8>? encryptionState;
  Uint8List? encryptionHeader;
  Pointer<Uint8>? decryptionState;
  Uint8List? decryptionKey;

  _SecretStream._({
    required Pointer<Uint8> this.encryptionState,
    required Uint8List this.encryptionHeader,
    required Uint8List this.decryptionKey,
  });

  @override
  SecretStreamDecryptionResult decryptPackage(
    Uint8List encrypted, {
    Uint8List? additionalData,
  }) {
    if (isDecryptionClosed) {
      throw SecretStreamClosedException(incoming: true);
    }
    return _wrapDecryptionFailure(() {
      final key = decryptionKey;
      if (key != null) {
        decryptionKey = null;
        final header =
            Uint8List.sublistView(encrypted, 0, Crypto.secretStreamHeaderBytes);
        encrypted =
            Uint8List.sublistView(encrypted, Crypto.secretStreamHeaderBytes);

        decryptionState =
            _sodium.Sodium.cryptoSecretstreamXchacha20poly1305InitPull(
                header, key);
      }

      final result = _sodium.Sodium.cryptoSecretstreamXchacha20poly1305Pull(
        decryptionState!,
        encrypted,
        additionalData,
      );
      final tag = SecretStream.intToTag(result.tag);
      if (tag == SecretStreamTag.finalMessage) {
        decryptionState = null;
      }
      return SecretStreamDecryptionResult(result.m, tag);
    });
  }

  @override
  Uint8List encryptPackage(
    Uint8List message, {
    Uint8List? additionalData,
    SecretStreamTag tag = SecretStreamTag.message,
  }) {
    if (isEncryptionClosed) {
      throw SecretStreamClosedException(incoming: false);
    }
    final result = _sodium.Sodium.cryptoSecretstreamXchacha20poly1305Push(
      encryptionState!,
      message,
      additionalData,
      SecretStream.tagToInt(tag),
    );
    if (tag == SecretStreamTag.finalMessage) {
      encryptionState = null;
    }
    final header = encryptionHeader;
    if (header == null) {
      return result;
    } else {
      encryptionHeader = null;
      final bytes = BytesBuilder(copy: false)
        ..add(header)
        ..add(result);
      return bytes.takeBytes();
    }
  }

  @override
  bool get isDecryptionClosed =>
      decryptionState == null && decryptionKey == null;

  @override
  bool get isEncryptionClosed => encryptionState == null;
}
