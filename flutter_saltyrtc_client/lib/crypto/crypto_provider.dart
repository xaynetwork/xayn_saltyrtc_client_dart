import 'package:dart_saltyrtc_client/dart_saltyrtc_client.dart' show Crypto;

import 'crypto_provider_stub.dart'
    if (dart.library.io) 'crypto_provider_dart.dart'
    if (dart.library.js) 'crypto_provider_web.dart';

abstract class CryptoProvider {
  CryptoProvider._();

  static Future init() async {
    await initCrypto();
  }

  static Crypto get instance => cryptoInstance;
}

bool _init = false;

Future<Crypto> getCrypto() async {
  if (!_init) {
    await initCrypto();
    _init = true;
  }

  return crypto();
}

Crypto crypto() {
  return cryptoInstance;
}
