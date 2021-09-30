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

/// Event indicating that the initiator could not decrypt the message send from us.
///
/// This is only produced by responder clients during the client to client
/// handshake.
///
/// This mainly happens in following situations:
///
/// - The wrong auth token is used.
/// - A auth token was required but not used.
/// - A auth token was not required but send.
/// - The responders permanent key doesn't match the expected
///   trusted responders key.
///
/// Some (but not all) potential situations in which this can happen are:
///
/// - The responder did "fall over" (e.g. disconnect) during a previous handshake
///   and is already trusted, but believes it's not yet trusted (as the initiator
///   potentially trusts the client once it receives the auth msg, but before it
///   responded with an auth msg).
///
/// - Multiple devices somehow got the same auth token (e.g. they scanned the
///   same QR code).
//TODO use when we detect closing if the could not decrypt close code.
@immutable
class InitiatorCouldNotDecrypt extends Event {}
