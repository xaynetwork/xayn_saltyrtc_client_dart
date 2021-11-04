/// Exposes the internally used crypto utilities.
///
/// This allows us to not import/include libsodium twice,
/// but in the future there should be an independent package.
library crypto;

export 'package:dart_saltyrtc_client/crypto.dart';
export 'package:flutter_saltyrtc_client/src/crypto/crypto_provider.dart'
    show getCrypto;
