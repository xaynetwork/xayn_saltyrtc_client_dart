import 'dart:math' show Random, min;
import 'dart:typed_data' show BytesBuilder, Uint8List;

import 'package:collection/collection.dart' show ListEquality;
import 'package:equatable/equatable.dart' show Equatable;
import 'package:fixnum/fixnum.dart' show Int64;
import 'package:meta/meta.dart' show immutable;
import 'package:xayn_saltyrtc_client/src/crypto/crypto.dart'
    show SharedKeyStore, Crypto, AuthToken, KeyStore, DecryptionFailedException;
import 'package:xayn_saltyrtc_client/src/crypto/crypto.dart'
    show
        AuthToken,
        Crypto,
        DecryptionFailedException,
        KXSecretStreamBuilder,
        KeyStore,
        SharedKeyStore;
import 'package:xayn_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;

const listEq = ListEquality<int>();

typedef _KeyId = int;
typedef _MessageId = Int64;

@immutable
class _MockKeyStore extends KeyStore {
  final _KeyId _keyId;
  final MockCrypto crypto;

  _MockKeyStore({
    required this.crypto,
    required Uint8List publicKey,
    required Uint8List privateKey,
  })  : _keyId = crypto._nextKeyId(),
        super(publicKey: publicKey, privateKey: privateKey);
}

@immutable
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
      keyId: _keyId,
      ciphertext: ciphertext,
      nonce: nonce,
    );
  }

  @override
  Uint8List encrypt({
    required Uint8List message,
    required Uint8List nonce,
  }) {
    return crypto._encryptWith(keyId: _keyId, message: message, nonce: nonce);
  }
}

@immutable
class _MockAuthToken extends AuthToken {
  final _KeyId _keyId;
  final MockCrypto crypto;

  @override
  final Uint8List bytes;

  _MockAuthToken(this.bytes, this.crypto) : _keyId = crypto._nextKeyId();

  @override
  Uint8List decrypt({
    required Uint8List ciphertext,
    required Uint8List nonce,
  }) {
    return crypto._decryptWith(
      keyId: _keyId,
      ciphertext: ciphertext,
      nonce: nonce,
    );
  }

  @override
  Uint8List encrypt({required Uint8List message, required Uint8List nonce}) {
    return crypto._encryptWith(keyId: _keyId, message: message, nonce: nonce);
  }
}

@immutable
class EncryptionInfo {
  final Uint8List decryptedData;
  final Uint8List nonce;
  final _KeyId keyId;

  const EncryptionInfo({
    required this.keyId,
    required this.decryptedData,
    required this.nonce,
  });
}

@immutable
class _TwoKeyIds extends Equatable {
  @override
  final List<Object?> props;

  _TwoKeyIds(_KeyId first, _KeyId second)
      : props = first < second ? [first, second] : [second, first];
}

@immutable
class _KeyBytes extends Equatable {
  @override
  final List<Object?> props;

  _KeyBytes(Uint8List data) : props = data.sublist(0);
}

class MockCrypto extends Crypto {
  static const List<int> magicNumber = [123, 249, 27, 55];

  final _random = Random();

  /// _KeyId used for encryption -> _MessageId of encrypted message -> decrypted message
  Map<_MessageId, EncryptionInfo> encryptedMessages = {};

  /// Public/Private key => Key
  Map<_KeyBytes, _MockKeyStore> keyStoreLookUp = {};

  /// AuthToken lookup
  Map<_KeyBytes, _MockAuthToken> authTokenLookUp = {};

  /// TowKeyIds(keyIdOfA, keyIdOfB) => SharedKeyStore
  Map<_TwoKeyIds, SharedKeyStore> sharedKeyStoreLookUp = {};

  _KeyId _nextKeyIdState = 0;
  _MessageId _nextMessageIdState = Int64(0);

  _KeyId _nextKeyId() => _nextKeyIdState++;
  _MessageId _nextMessageId() => _nextMessageIdState++;

  MockCrypto();

  void _reset() {
    encryptedMessages = {};
    keyStoreLookUp = {};
    authTokenLookUp = {};
    sharedKeyStoreLookUp = {};
  }

  @override
  AuthToken createAuthToken() {
    return createAuthTokenFromToken(token: randomBytes(Crypto.symmKeyBytes));
  }

  @override
  AuthToken createAuthTokenFromToken({required Uint8List token}) {
    return authTokenLookUp.putIfAbsent(
      _KeyBytes(token),
      () => _MockAuthToken(token, this),
    );
  }

  @override
  KeyStore createKeyStore() {
    return createKeyStoreFromKeys(
      privateKey: randomBytes(Crypto.publicKeyBytes),
      publicKey: randomBytes(Crypto.privateKeyBytes),
    );
  }

  @override
  KeyStore createKeyStoreFromKeys({
    required Uint8List privateKey,
    required Uint8List publicKey,
  }) {
    final keyOfPrivateKey = _KeyBytes(privateKey);
    final keyOfPublicKey = _KeyBytes(publicKey);

    var keyStore = keyStoreLookUp[keyOfPrivateKey];
    if (keyStore == null) {
      keyStore = _MockKeyStore(
        crypto: this,
        publicKey: publicKey,
        privateKey: privateKey,
      );
      assert(!keyStoreLookUp.containsKey(keyOfPublicKey));
      assert(!keyStoreLookUp.containsKey(keyOfPublicKey));
      keyStoreLookUp[keyOfPrivateKey] = keyStore;
      keyStoreLookUp[keyOfPublicKey] = keyStore;
    }
    return keyStore;
  }

  @override
  SharedKeyStore createSharedKeyStore({
    required KeyStore ownKeyStore,
    required Uint8List remotePublicKey,
  }) {
    final firstKeyId =
        keyStoreLookUp[_KeyBytes(ownKeyStore.privateKey)]!._keyId;
    final secondKeyId = keyStoreLookUp[_KeyBytes(remotePublicKey)]!._keyId;
    return sharedKeyStoreLookUp.putIfAbsent(
      _TwoKeyIds(firstKeyId, secondKeyId),
      () => _MockSharedKeyStore(
        crypto: this,
        ownPrivateKey: ownKeyStore.privateKey,
        remotePublicKey: remotePublicKey,
      ),
    );
  }

  @override
  Uint8List randomBytes(int size) {
    return Uint8List.fromList(List.generate(size, (_) => _random.nextInt(255)));
  }

  KeyStore? getKeyStoreForKey(Uint8List key) {
    return keyStoreLookUp[_KeyBytes(key)];
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
    final messageIdBytes = messageId.toBytes();
    final expectedLength = message.length + Crypto.boxOverhead;
    final currentLength = magicNumber.length + messageIdBytes.length;
    assert(currentLength <= expectedLength);
    final bytes = BytesBuilder(copy: false)
      ..add(magicNumber)
      ..add(messageIdBytes)
      ..add(Uint8List(expectedLength - currentLength));
    return bytes.takeBytes();
  }

  Uint8List _decryptWith({
    required _KeyId keyId,
    required Uint8List ciphertext,
    required Uint8List nonce,
  }) {
    Crypto.checkNonce(nonce);
    final foundMagicNumber =
        Uint8List.sublistView(ciphertext, 0, magicNumber.length);
    if (!listEq.equals(foundMagicNumber, magicNumber)) {
      throw const DecryptionFailedException(
        "Can't decrypt something which wasn't encrypted with the mock.",
      );
    }

    final messageId = Int64.fromBytes(
      Uint8List.sublistView(
        ciphertext,
        magicNumber.length,
        min(magicNumber.length + 8, ciphertext.length),
      ),
    );

    final info = encryptedMessages[messageId]!;
    if (info.keyId != keyId) {
      throw const DecryptionFailedException(
        'Message was encrypted with different key.',
      );
    }
    if (!listEq.equals(info.nonce, nonce)) {
      final expectedNonce = Nonce.fromBytes(info.nonce);
      final receivedNonce = Nonce.fromBytes(nonce);
      throw DecryptionFailedException(
        'Message was encrypted with different nonce:\nexpected = $expectedNonce\nreceived = $receivedNonce',
      );
    }
    return info.decryptedData;
  }

  @override
  KXSecretStreamBuilder createKXSecretStreamBuilder({
    required bool onePeerTrueOneFalse,
  }) {
    throw UnimplementedError();
  }
}

/// Setup crypto.
///
/// Call (at most) once per test file.
///
/// Do not call before/after each test.
void setUpCrypto() {
  crypto._reset();
}

final crypto = MockCrypto();
