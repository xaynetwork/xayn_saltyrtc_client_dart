import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/src/messages/close_code.dart'
    show CloseCode;
import 'package:dart_saltyrtc_client/src/protocol/error.dart'
    show SaltyRtcError;
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

@immutable
class NoSharedTaskFound extends Event {
  static Exception signalAndException(Sink<Event> eventOut) {
    eventOut.add(NoSharedTaskFound());
    return SaltyRtcError(
        CloseCode.goingAway, 'going away after no shared task was found');
  }
}
