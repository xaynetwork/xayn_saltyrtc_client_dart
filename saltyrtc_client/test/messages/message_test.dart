import 'dart:typed_data' show Uint8List;

import 'package:test/test.dart';
import 'package:xayn_saltyrtc_client/src/messages/c2c/token.dart' show Token;
import 'package:xayn_saltyrtc_client/src/messages/id.dart' show Id;
import 'package:xayn_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;
import 'package:xayn_saltyrtc_client/src/messages/s2c/server_hello.dart'
    show ServerHello;

import '../crypto_mock.dart' show crypto;
import '../utils.dart' show setUpTesting;

void main() {
  setUpTesting();

  group('buildPackage', () {
    test('without encryption', () {
      final key = crypto.createKeyStore();
      final msg = ServerHello(key.publicKey);
      final msgBytes = msg.toBytes();
      final nonce = Nonce.fromRandom(
        source: Id.responderId(12),
        destination: Id.serverAddress,
        randomBytes: crypto.randomBytes,
      );
      final nonceBytes = nonce.toBytes();
      final package = msg.buildPackage(nonce, encryptWith: null);
      expect(Uint8List.sublistView(package, 0, Nonce.totalLength),
          equals(nonceBytes));
      expect(
          Uint8List.sublistView(package, Nonce.totalLength), equals(msgBytes));
    });

    test('encrypted', () {
      final token = crypto.createAuthToken();
      final msg = Token(token.bytes);
      final msgBytes = msg.toBytes();
      final nonce = Nonce.fromRandom(
        source: Id.responderId(12),
        destination: Id.initiatorAddress,
        randomBytes: crypto.randomBytes,
      );
      final nonceBytes = nonce.toBytes();
      final package = msg.buildPackage(nonce, encryptWith: token);
      expect(Uint8List.sublistView(package, 0, Nonce.totalLength),
          equals(nonceBytes));
      final decryptedBytes = token.decrypt(
          ciphertext: Uint8List.sublistView(package, Nonce.totalLength),
          nonce: nonceBytes);
      expect(msgBytes, equals(decryptedBytes));
    });
  });
}
