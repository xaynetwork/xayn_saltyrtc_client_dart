///
/// Most times you want to use a client like following:
///
/// ```dart
/// try {
///   await for(final event in client.run()) {
///     // handle event
///   }
///   // normal closed/completed task
/// } on ClosingErrorEvent catch (e, st) {
///   // handle error
/// }
/// ```
library flutter_saltyrtc_client;

export 'package:xayn_flutter_saltyrtc_client/src/client.dart'
    show InitiatorClient, ResponderClient;
export 'package:xayn_saltyrtc_client/dart_saltyrtc_client.dart' show logger;
