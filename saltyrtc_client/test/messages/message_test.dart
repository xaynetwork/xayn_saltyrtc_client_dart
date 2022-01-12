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
      expect(
        Uint8List.sublistView(package, 0, Nonce.totalLength),
        equals(nonceBytes),
      );
      expect(
        Uint8List.sublistView(package, Nonce.totalLength),
        equals(msgBytes),
      );
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
      expect(
        Uint8List.sublistView(package, 0, Nonce.totalLength),
        equals(nonceBytes),
      );
      final decryptedBytes = token.decrypt(
        ciphertext: Uint8List.sublistView(package, Nonce.totalLength),
        nonce: nonceBytes,
      );
      expect(msgBytes, equals(decryptedBytes));
    });
  });
}
