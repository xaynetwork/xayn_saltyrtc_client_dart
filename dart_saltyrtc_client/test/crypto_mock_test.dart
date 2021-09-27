import 'package:dart_saltyrtc_client/src/messages/id.dart' show Id;
import 'package:dart_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;
import 'package:test/test.dart';

import 'crypto_mock.dart' show crypto;
import 'utils.dart';

void main() {
  setUpTesting();

  final id1 = Id.serverAddress;
  final id2 = Id.initiatorAddress;

  group('crypto using shared key store', () {
    test('lookup KeyStore based on key bytes', () {
      final key1 = crypto.createKeyStore();
      final key2 = crypto.createKeyStoreFromKeys(
          privateKey: key1.publicKey, publicKey: key1.publicKey);
      expect(key1, same(key2));
    });

    test('lookup AuthToken based on key bytes', () {
      final token1 = crypto.createAuthToken();
      final token2 = crypto.createAuthTokenFromToken(token: token1.bytes);
      expect(token1, same(token2));
    });

    test('two KeyStores have the same SahredKeyStore', () {
      final key1 = crypto.createKeyStore();
      final key2 = crypto.createKeyStore();
      final sharedKeyStore1 = crypto.createSharedKeyStore(
          ownKeyStore: key1, remotePublicKey: key2.publicKey);
      final sharedKeyStore2 = crypto.createSharedKeyStore(
          ownKeyStore: key2, remotePublicKey: key1.publicKey);
      expect(sharedKeyStore1, same(sharedKeyStore2));
    });

    test('using KeyStore.decrypt', () {
      final message = crypto.randomBytes(10);
      final nonce = Nonce.fromRandom(
          source: id1, destination: id2, randomBytes: crypto.randomBytes);

      final key1 = crypto.createKeyStore();
      final key2 = crypto.createKeyStore();
      final sharedKeyOf1 = crypto.createSharedKeyStore(
          ownKeyStore: key1, remotePublicKey: key2.publicKey);

      final encrypted =
          sharedKeyOf1.encrypt(message: message, nonce: nonce.toBytes());
      final decrypted = key2.decrypt(
          remotePublicKey: key1.publicKey,
          ciphertext: encrypted,
          nonce: nonce.toBytes());

      expect(decrypted, equals(message));
    });

    test('using a second shared key', () {
      final message = crypto.randomBytes(10);
      final nonce = Nonce.fromRandom(
          source: id1, destination: id2, randomBytes: crypto.randomBytes);

      final key1 = crypto.createKeyStore();
      final key2 = crypto.createKeyStore();
      final sharedKeyOf1 = crypto.createSharedKeyStore(
          ownKeyStore: key1, remotePublicKey: key2.publicKey);
      final sharedKeyOf2 = crypto.createSharedKeyStore(
          ownKeyStore: key2, remotePublicKey: key1.publicKey);

      final encrypted =
          sharedKeyOf1.encrypt(message: message, nonce: nonce.toBytes());
      final decrypted =
          sharedKeyOf2.decrypt(ciphertext: encrypted, nonce: nonce.toBytes());

      expect(decrypted, equals(message));
    });
  });
}
