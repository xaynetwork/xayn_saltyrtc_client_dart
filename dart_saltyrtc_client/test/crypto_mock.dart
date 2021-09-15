import 'dart:math' show Random;
import 'dart:typed_data' show BytesBuilder, Uint8List;

import 'package:collection/collection.dart' show ListEquality;
import 'package:dart_saltyrtc_client/dart_saltyrtc_client.dart';
import 'package:dart_saltyrtc_client/src/crypto/crypto.dart'
    show SharedKeyStore, Crypto, AuthToken, KeyStore;
import 'package:dart_saltyrtc_client/src/messages/nonce/nonce.dart';
import 'package:fixnum/fixnum.dart' show Int64;

final listEq = ListEquality<int>();

typedef _KeyId = int;
typedef _MessageId = Int64;

class _MockKeyStore extends KeyStore {
  final _KeyId _keyId;
  final MockCrypto crypto;

  _MockKeyStore({
    required this.crypto,
    required Uint8List publicKey,
    required Uint8List privateKey,
  })  : _keyId = crypto._nextKeyId(),
        super(publicKey: publicKey, privateKey: privateKey);

  @override
  Uint8List decrypt(
      {required Uint8List remotePublicKey,
      required Uint8List ciphertext,
      required Uint8List nonce}) {
    final sks = crypto.createSharedKeyStore(
        ownKeyStore: this, remotePublicKey: remotePublicKey);
    return sks.decrypt(ciphertext: ciphertext, nonce: nonce);
  }
}

class _MockSharedKeyStore extends SharedKeyStore {
  final _KeyId _keyId;
  final MockCrypto crypto;

  _MockSharedKeyStore({
    required this.crypto,
    required Uint8List ownPrivateKey,
    required Uint8List remotePublicKey,
  })  : _keyId = crypto._nextKeyId(),
        super(ownPrivateKey: ownPrivateKey, remotePublicKey: remotePublicKey);

  @override
  Uint8List decrypt({
    required Uint8List ciphertext,
    required Uint8List nonce,
  }) {
    return crypto._decryptWith(
        keyId: _keyId, ciphertext: ciphertext, nonce: nonce);
  }

  @override
  Uint8List encrypt({
    required Uint8List message,
    required Uint8List nonce,
  }) {
    return crypto._encryptWith(keyId: _keyId, message: message, nonce: nonce);
  }
}

class _MockAuthToken extends AuthToken {
  final _KeyId _keyId;
  final MockCrypto crypto;

  _MockAuthToken(this.crypto) : _keyId = crypto._nextKeyId();

  @override
  Uint8List decrypt({
    required Uint8List ciphertext,
    required Uint8List nonce,
  }) {
    return crypto._decryptWith(
        keyId: _keyId, ciphertext: ciphertext, nonce: nonce);
  }

  @override
  Uint8List encrypt({required Uint8List message, required Uint8List nonce}) {
    return crypto._encryptWith(keyId: _keyId, message: message, nonce: nonce);
  }
}

class EncryptionInfo {
  final Uint8List decryptedData;
  final Uint8List nonce;
  final _KeyId keyId;

  EncryptionInfo({
    required this.keyId,
    required this.decryptedData,
    required this.nonce,
  });
}

class MockCrypto extends Crypto {
  static const int magicByte = 120;

  final _random = Random();

  /// _KeyId used for encryption -> _MessageId of encrypted message -> decrypted message
  Map<_MessageId, EncryptionInfo> encryptedMessages = {};

  /// Public/Private key => Key
  Map<Uint8List, _MockKeyStore> keyStoreLookUp = {};

  /// AuthToken lookup
  Map<Uint8List, _MockAuthToken> authTokenLookUp = {};

  /// KeyId => SharedKeyStore
  Map<Set<_KeyId>, SharedKeyStore> sharedKeyStoreLookUp = {};

  _KeyId _nextKeyIdState = 0;
  _MessageId _nextMessageIdState = Int64(0);

  _KeyId _nextKeyId() => _nextKeyIdState++;
  _MessageId _nextMessageId() => _nextMessageIdState++;

  @override
  AuthToken createAuthToken() {
    return createAuthTokenFromToken(token: randomBytes(Crypto.symmKeyBytes));
  }

  @override
  AuthToken createAuthTokenFromToken({required Uint8List token}) {
    return authTokenLookUp.putIfAbsent(token, () => _MockAuthToken(this));
  }

  @override
  KeyStore createKeyStore() {
    return createKeyStoreFromKeys(
        privateKey: randomBytes(Crypto.publicKeyBytes),
        publicKey: randomBytes(Crypto.privateKeyBytes));
  }

  @override
  KeyStore createKeyStoreFromKeys(
      {required Uint8List privateKey, required Uint8List publicKey}) {
    var keyStore = keyStoreLookUp[privateKey];
    if (keyStore == null) {
      keyStore = _MockKeyStore(
          crypto: this, publicKey: publicKey, privateKey: privateKey);
      _addNewKeyStore(keyStore);
    }
    return keyStore;
  }

  @override
  SharedKeyStore createSharedKeyStore(
      {required KeyStore ownKeyStore, required Uint8List remotePublicKey}) {
    final leftKeyId = keyStoreLookUp[ownKeyStore.privateKey]!._keyId;
    final rightKeyId = keyStoreLookUp[remotePublicKey]!._keyId;
    return sharedKeyStoreLookUp.putIfAbsent(
        {leftKeyId, rightKeyId},
        () => _MockSharedKeyStore(
              crypto: this,
              ownPrivateKey: ownKeyStore.privateKey,
              remotePublicKey: remotePublicKey,
            ));
  }

  @override
  Uint8List randomBytes(int size) {
    return Uint8List.fromList(List.generate(size, (_) => _random.nextInt(255)));
  }

  void _addNewKeyStore(_MockKeyStore keyStore) {
    assert(!keyStoreLookUp.containsKey(keyStore.publicKey));
    assert(!keyStoreLookUp.containsKey(keyStore.privateKey));
    keyStoreLookUp[keyStore.privateKey] = keyStore;
    keyStoreLookUp[keyStore.publicKey] = keyStore;
  }

  Uint8List _encryptWith({
    required _KeyId keyId,
    required Uint8List message,
    required Uint8List nonce,
  }) {
    final messageId = _nextMessageId();
    encryptedMessages[messageId] = EncryptionInfo(
      decryptedData: message,
      nonce: nonce,
      keyId: keyId,
    );

    final bytes = BytesBuilder(copy: false);
    bytes
      ..add(
          Uint8List.fromList(List.generate(Crypto.boxOverhead, (index) => magicByte)))
      ..add(messageId.toBytes());
    return bytes.takeBytes();
  }

  Uint8List _decryptWith({
    required _KeyId keyId,
    required Uint8List ciphertext,
    required Uint8List nonce,
  }) {
    Crypto.checkNonce(nonce);
    //ignore: omit_local_variable_types
    bool validMagicCookie =
        ciphertext.length > Crypto.boxOverhead &&
        Uint8List.sublistView(ciphertext, 0, Crypto.boxOverhead)
            .fold(true, (valid, element) => valid & (element == magicByte));
    if (!validMagicCookie) {
      throw Exception(
          "Can't decrypt something which wasn't encrypted with the mock.");
    }
    final messageId =
        Int64.fromBytes(Uint8List.sublistView(ciphertext, Crypto.boxOverhead));
    final info = encryptedMessages[messageId]!;
    if (info.keyId != keyId) {
      throw AssertionError('Message was encrypted with different key.');
    }
    if (!listEq.equals(info.nonce, nonce)) {
      final expectedNonce = Nonce.fromBytes(info.nonce);
      final receivedNonce = Nonce.fromBytes(nonce);
      throw AssertionError(
          'Message was encrypted with different nonce:\nexpected = $expectedNonce\nreceived = $receivedNonce');
    }
    return info.decryptedData;
  }
}
