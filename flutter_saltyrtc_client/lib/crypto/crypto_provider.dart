import 'package:dart_saltyrtc_client/dart_saltyrtc_client.dart';

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
