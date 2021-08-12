import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/dart_saltyrtc_client.dart' show Crypto;

void _checkLength(Uint8List data, int expected, String name) {
  final len = data.length;
  if (len != expected) {
    throw ArgumentError('$name must be $expected, found $len');
  }
}

void checkNonce(Uint8List nonce) {
  _checkLength(nonce, Crypto.nonceBytes, 'nonce');
}

void checkPublicKey(Uint8List publicKey) {
  _checkLength(publicKey, Crypto.publicKeyBytes, 'public key');
}

void checkPrivateKey(Uint8List privateKey) {
  _checkLength(privateKey, Crypto.privateKeyBytes, 'private key');
}

void checkSymmetricKey(Uint8List symmKey) {
  _checkLength(symmKey, Crypto.symmKeyBytes, 'symmetric key');
}
