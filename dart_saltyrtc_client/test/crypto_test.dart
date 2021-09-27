import 'package:dart_saltyrtc_client/src/crypto/crypto.dart'
    show InitialClientAuthMethod;
import 'package:test/test.dart';

import 'crypto_mock.dart' show crypto;
import 'utils.dart';

void main() {
  setUpTesting();

  group('InitialClientAuthMethod', () {
    final permPubKey1 = crypto.createKeyStore();
    final permPubKey2 = crypto.createKeyStore();

    test('is only exactly one specific method', () {
      expect(() {
        InitialClientAuthMethod.fromEither(
          authToken: crypto.createAuthToken(),
          trustedResponderPermanentPublicKey: permPubKey1.publicKey,
          initiatorPermanentKeys: permPubKey2,
          crypto: crypto,
        );
      }, throwsArgumentError);
      expect(() {
        InitialClientAuthMethod.fromEither(
          authToken: null,
          trustedResponderPermanentPublicKey: null,
          initiatorPermanentKeys: permPubKey2,
          crypto: crypto,
        );
      }, throwsArgumentError);
    });

    test(
        'fromEither only requires crypto/initiatorPermanentKeys for trusted responder',
        () {
      final authToken = crypto.createAuthToken();
      final authMethod =
          InitialClientAuthMethod.fromEither(authToken: authToken);
      expect(authMethod.authToken, same(authToken));
      expect(authMethod.trustedResponderSharedKey, isNull);
      expect(() {
        InitialClientAuthMethod.fromEither(
          trustedResponderPermanentPublicKey: permPubKey1.publicKey,
        );
      }, throwsArgumentError);
    });

    test('creates the right key', () {
      final authMethod = InitialClientAuthMethod.fromEither(
          trustedResponderPermanentPublicKey: permPubKey1.publicKey,
          initiatorPermanentKeys: permPubKey2,
          crypto: crypto);
      final expectedKey = crypto.createSharedKeyStore(
          ownKeyStore: permPubKey2, remotePublicKey: permPubKey1.publicKey);
      expect(authMethod.trustedResponderSharedKey, same(expectedKey));
      expect(authMethod.authToken, isNull);
    });
  });
}
