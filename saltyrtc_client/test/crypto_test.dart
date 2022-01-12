// Copyright 2021 Xayn AG
//
// Licensed under the Apache License, Version 2.0 (the License);
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'package:test/test.dart';
import 'package:xayn_saltyrtc_client/src/crypto/crypto.dart'
    show InitialClientAuthMethod, SecretStream, SecretStreamTag;

import 'crypto_mock.dart' show crypto;
import 'utils.dart' show setUpTesting;

void main() {
  setUpTesting();

  group('InitialClientAuthMethod', () {
    final permPubKey1 = crypto.createKeyStore();
    final permPubKey2 = crypto.createKeyStore();

    test('is only exactly one specific method', () {
      expect(
        () {
          InitialClientAuthMethod.fromEither(
            authToken: crypto.createAuthToken(),
            trustedResponderPermanentPublicKey: permPubKey1.publicKey,
            initiatorPermanentKeys: permPubKey2,
            crypto: crypto,
          );
        },
        throwsArgumentError,
      );
      expect(
        () {
          InitialClientAuthMethod.fromEither(
            authToken: null,
            trustedResponderPermanentPublicKey: null,
            initiatorPermanentKeys: permPubKey2,
            crypto: crypto,
          );
        },
        throwsArgumentError,
      );
    });

    test(
        'fromEither only requires crypto/initiatorPermanentKeys for trusted responder',
        () {
      final authToken = crypto.createAuthToken();
      final authMethod =
          InitialClientAuthMethod.fromEither(authToken: authToken);
      expect(authMethod.authToken, same(authToken));
      expect(authMethod.trustedResponderSharedKey, isNull);
      expect(
        () {
          InitialClientAuthMethod.fromEither(
            trustedResponderPermanentPublicKey: permPubKey1.publicKey,
          );
        },
        throwsArgumentError,
      );
    });

    test('creates the right key', () {
      final authMethod = InitialClientAuthMethod.fromEither(
        trustedResponderPermanentPublicKey: permPubKey1.publicKey,
        initiatorPermanentKeys: permPubKey2,
        crypto: crypto,
      );
      final expectedKey = crypto.createSharedKeyStore(
        ownKeyStore: permPubKey2,
        remotePublicKey: permPubKey1.publicKey,
      );
      expect(authMethod.trustedResponderSharedKey, same(expectedKey));
      expect(authMethod.authToken, isNull);
    });
  });

  test('from to int conversion works for tag', () {
    void test1(int tag) {
      //ignore:invalid_use_of_protected_member
      expect(SecretStream.tagToInt(SecretStream.intToTag(tag)), equals(tag));
    }

    test1(0);
    test1(1);
    test1(2);
    test1(3);

    void test2(SecretStreamTag tag) {
      //ignore:invalid_use_of_protected_member
      expect(SecretStream.intToTag(SecretStream.tagToInt(tag)), equals(tag));
    }

    test2(SecretStreamTag.message);
    test2(SecretStreamTag.push);
    test2(SecretStreamTag.rekey);
    test2(SecretStreamTag.finalMessage);

    expect(
      () {
        test1(4);
      },
      throwsArgumentError,
    );
    expect(
      () {
        test1(-1);
      },
      throwsArgumentError,
    );
  });
}
