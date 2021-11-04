import 'dart:js' show JsObject;
import 'dart:typed_data' show BytesBuilder, Uint8List;

import 'package:dart_saltyrtc_client/crypto.dart'
    show
        AuthToken,
        Crypto,
        DecryptionFailedException,
        KXSecretStreamBuilder,
        KeyStore,
        SecretStream,
        SecretStreamTag,
        SecretStreamClosedException,
        SecretStreamDecryptionResult,
        SharedKeyStore;
import 'package:flutter_saltyrtc_client/src/crypto/load_sodiumjs.dart'
    show loadSodiumInBrowser;
import 'package:flutter_saltyrtc_client/src/crypto/sodium.js.dart'
    show KeyPair, LibSodiumJS;

Future<Crypto> loadCrypto() async {
  final sodiumJs = await loadSodiumInBrowser();
  return _JSCrypto(sodiumJs);
}

T _wrapDecryptionFailure<T>(T Function() code) {
  try {
    return code();
  } on JsObject catch (cause) {
    if (cause.hasProperty('message') &&
        cause['message'] == 'incorrect secret key for the given ciphertext') {
      throw DecryptionFailedException(cause);
    } else {
      rethrow;
    }
  }
}

class _JSKeyStore extends KeyStore {
  _JSKeyStore({
    required Uint8List publicKey,
    required Uint8List privateKey,
  }) : super(publicKey: publicKey, privateKey: privateKey);
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
    return _wrapDecryptionFailure(() =>
        _sodium.crypto_box_open_easy_afternm(ciphertext, nonce, _sharedKey));
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
  @override
  final Uint8List bytes;

  _JSAuthToken({
    required LibSodiumJS sodium,
    required Uint8List authToken,
  })  : _sodium = sodium,
        bytes = authToken {
    Crypto.checkSymmetricKey(bytes);
  }

  @override
  Uint8List decrypt({
    required Uint8List ciphertext,
    required Uint8List nonce,
  }) {
    Crypto.checkNonce(nonce);
    return _wrapDecryptionFailure(
        () => _sodium.crypto_secretbox_open_easy(ciphertext, nonce, bytes));
  }

  @override
  Uint8List encrypt({
    required Uint8List message,
    required Uint8List nonce,
  }) {
    Crypto.checkNonce(nonce);
    return _sodium.crypto_secretbox_easy(message, nonce, bytes);
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
    return _JSKeyStore(
        privateKey: keyPair.privateKey, publicKey: keyPair.publicKey);
  }

  @override
  KeyStore createKeyStoreFromKeys({
    required Uint8List publicKey,
    required Uint8List privateKey,
  }) {
    return _JSKeyStore(publicKey: publicKey, privateKey: privateKey);
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

  @override
  _KXSecretStreamBuilder createKXSecretStreamBuilder(
          {required bool isServer}) =>
      _KXSecretStreamBuilder(_sodium, _sodium.crypto_kx_keypair(), isServer);
}

class _KXSecretStreamBuilder extends KXSecretStreamBuilder {
  final LibSodiumJS _sodium;
  final KeyPair keyPair;
  final bool isServer;

  @override
  Uint8List get publicKey => keyPair.publicKey;

  _KXSecretStreamBuilder(this._sodium, this.keyPair, this.isServer);

  @override
  _SecretStream build(Uint8List peerPublicKey) {
    final mkKeys = isServer
        ? _sodium.crypto_kx_server_session_keys
        : _sodium.crypto_kx_client_session_keys;
    final sessionKeys =
        mkKeys(keyPair.publicKey, keyPair.privateKey, peerPublicKey);
    final initPushResult = _sodium
        .crypto_secretstream_xchacha20poly1305_init_push(sessionKeys.sharedTx);
    final stream = _SecretStream._(
      _sodium,
      encryptionState: initPushResult.state,
      encryptionHeader: initPushResult.header,
      decryptionKey: sessionKeys.sharedRx,
    );
    return stream;
  }
}

class _SecretStream extends SecretStream {
  final LibSodiumJS _sodium;
  num? encryptionState;
  Uint8List? encryptionHeader;
  num? decryptionState;
  Uint8List? decryptionKey;

  _SecretStream._(
    LibSodiumJS sodium, {
    required num this.encryptionState,
    required Uint8List this.encryptionHeader,
    required Uint8List this.decryptionKey,
  }) : _sodium = sodium;

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

        decryptionState = _sodium
            .crypto_secretstream_xchacha20poly1305_init_pull(header, key);
      }

      final result = _sodium.crypto_secretstream_xchacha20poly1305_pull(
        decryptionState!,
        encrypted,
        additionalData,
      );
      final tag = SecretStream.intToTag(result.tag as int);
      if (tag == SecretStreamTag.finalMessage) {
        decryptionState = null;
      }
      return SecretStreamDecryptionResult(result.message, tag);
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
    final result = _sodium.crypto_secretstream_xchacha20poly1305_push(
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
