import 'dart:typed_data' show Uint8List;

import 'package:meta/meta.dart' show immutable;

abstract class Event {}

@immutable
class ServerHandshakeDone extends Event {}

@immutable
class ResponderAuthenticated extends Event {
  /// Permanent key of the responder.
  /// After this has been received the authentication token must not
  /// be used again, this key must be use instead.
  final Uint8List permanentKey;

  ResponderAuthenticated(this.permanentKey);
}
