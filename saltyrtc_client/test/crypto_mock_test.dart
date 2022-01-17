// Copyright 2021 Xayn AG
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'package:test/test.dart';
import 'package:xayn_saltyrtc_client/src/messages/id.dart' show Id;
import 'package:xayn_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;

import 'crypto_mock.dart' show crypto;
import 'utils.dart' show setUpTesting;

void main() {
  setUpTesting();

  final id1 = Id.serverAddress;
  final id2 = Id.initiatorAddress;

  group('crypto using shared key store', () {
    test('lookup KeyStore based on key bytes', () {
      final key1 = crypto.createKeyStore();
      final key2 = crypto.createKeyStoreFromKeys(
        privateKey: key1.publicKey,
        publicKey: key1.publicKey,
      );
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
        ownKeyStore: key1,
        remotePublicKey: key2.publicKey,
      );
      final sharedKeyStore2 = crypto.createSharedKeyStore(
        ownKeyStore: key2,
        remotePublicKey: key1.publicKey,
      );
      expect(sharedKeyStore1, same(sharedKeyStore2));
    });

    test('using a second shared key', () {
      final message = crypto.randomBytes(10);
      final nonce = Nonce.fromRandom(
        source: id1,
        destination: id2,
        randomBytes: crypto.randomBytes,
      );

      final key1 = crypto.createKeyStore();
      final key2 = crypto.createKeyStore();
      final sharedKeyOf1 = crypto.createSharedKeyStore(
        ownKeyStore: key1,
        remotePublicKey: key2.publicKey,
      );
      final sharedKeyOf2 = crypto.createSharedKeyStore(
        ownKeyStore: key2,
        remotePublicKey: key1.publicKey,
      );

      final encrypted =
          sharedKeyOf1.encrypt(message: message, nonce: nonce.toBytes());
      final decrypted =
          sharedKeyOf2.decrypt(ciphertext: encrypted, nonce: nonce.toBytes());

      expect(decrypted, equals(message));
    });
  });
}
