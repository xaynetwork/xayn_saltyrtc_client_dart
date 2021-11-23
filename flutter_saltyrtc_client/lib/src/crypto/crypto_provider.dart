import 'package:xayn_saltyrtc_client/crypto.dart' show Crypto;

import 'crypto_provider_stub.dart'
    if (dart.library.io) 'crypto_provider_dart.dart'
    if (dart.library.js) 'crypto_provider_web.dart';

Future<Crypto>? _instance;
Future<Crypto> getCrypto() {
  _instance ??= loadCrypto();
  return _instance!;
}
