import 'package:dart_saltyrtc_client/dart_saltyrtc_client.dart' show Crypto;

/// Loads a crypto instance.
///
/// `getCrypto()` makes sure that this is only called once.
Future<Crypto> loadCrypto() {
  throw UnsupportedError('Cannot load crypto instance');
}
