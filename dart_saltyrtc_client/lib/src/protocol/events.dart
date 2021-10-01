import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/src/messages/close_code.dart'
    show CloseCode;
import 'package:dart_saltyrtc_client/src/protocol/error.dart'
    show SaltyRtcError;
import 'package:equatable/equatable.dart' show Equatable;
import 'package:meta/meta.dart' show immutable;

abstract class Event extends Equatable {
  @override
  List<Object?> get props => [];
}

@immutable
class ServerHandshakeDone extends Event {}

@immutable
class ResponderAuthenticated extends Event {
  /// Permanent key of the responder.
  /// After this has been received the authentication token must not
  /// be used again, this key must be use instead.
  final Uint8List permanentKey;

  ResponderAuthenticated(this.permanentKey);

  @override
  List<Object?> get props => [permanentKey];
}

/// Event emitted when a client disconnects from the path.
///
/// We diverge from the spec here as we don't report the client ID, the
/// reason for this is that it's completely useless as it is a arbitrary
/// given out an arbitrary re-used ID.
///
/// Instead we report what kind of peer disconnected.
///
/// A `unknownPeer` disconnecting can normally be ignored.
///
/// Many cases of `unauthenticatedTargetPeer` or `authenticatedPeer`
/// can point to the peer we want to connect to having some trouble,
/// likely a problematic internet connection.
///
@immutable
class Disconnected extends Event {
  final PeerKind peerKind;

  Disconnected(this.peerKind);
}

enum PeerKind {
  /// A peer about we don't really know anything.
  ///
  /// With the current version of SaltyRtc this can only be a responder which
  /// connected to the server but has not yet send any message to the client.
  unknownPeer,

  /// A peer from which we know that we will (probably) authenticate with it,
  /// but have not yet authenticated.
  ///
  /// For responders this is the initiator.
  ///
  /// For initiators this are responders from which they successfully received
  /// a message (which implies the responder either has the valid auth token or
  /// the private key for the trusted public key).
  unauthenticatedTargetPeer,

  /// A peer with which we completed a client to client handshake.
  authenticatedPeer,
}

/// Event emitted when sending a message to a client failed.
@immutable
class SendError extends Event {
  /// True if we already completed the client to client handshake.
  final bool wasAuthenticated;

  SendError({required this.wasAuthenticated});
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

/// The key we expect the server to use is not a key the server has.
@immutable
class IncompatibleServerKey extends Event {}

enum TempFailureVariant {
  /// We didn't responds with a pong to the servers ping.
  timeout,

  /// The WebRtc connection was closed without sending a close frame.
  ///
  /// This can e.g. happen in case of TCP realizing the connection
  /// to the server is gone, it's inherently similar to `timeout`.
  ///
  /// While this is not part of the SaltyRtc protocol it can happen anyway.
  abnormalClosure,

  /// 253 responders are currently connected to the server on given path.
  pathFull,

  /// The initiator dropped us.
  ///
  /// This can happen in two cases:
  ///
  /// - Many responder try to connect to the path and we are dropped as part of
  ///   the path cleaning.
  ///
  /// - The initiator is (was) paired with another responder, this should only be
  ///   possible if multiple devices/responder have the same auth data (same auth
  ///   token or same permanent keys). This case should normally not happen.
  ///
  /// While this error variant is likely temporary in case of the 2nd way it can
  /// happen it would be potential permanent, but we can't detect it.
  droppedByInitiator,

  /// The service is restarting and will be available again soon.
  ///
  /// While this is not part of the SaltyRtc protocol it can happen anyway.
  serviceRestart,

  /// The services asks us to try again later.
  ///
  /// While this is not part of the SaltyRtc protocol it can happen anyway.
  tryAgainLater,
}

/// A temporary failure happened.
///
/// Problems which are likely to go away if you try later again, it's *strongly*
/// recommended to use a form of "back-off" strategy an not retry immediately.
///
@immutable
class LikelyTemporaryFailure extends Event {
  final TempFailureVariant variant;

  LikelyTemporaryFailure(this.variant);

  @override
  List<Object?> get props => [variant];
}

enum UnexpectedStatusVariant {
  /// The server or other client ran into a internal error.
  ///
  /// Either `1011` (WebRtc) or `3002` SaltyRtc.
  internalError,

  /// The server or other client found we breached to protocol.
  ///
  /// This can be a
  ///
  /// - `1002`: WebRtc protocol error
  /// - `1003`: WebRtc unsupported data (should have been `3001`)
  /// - `1007`: WebRtc invalid frame payload data (should have been `3001`)
  /// - `3001`: SaltyRtc protocol error
  ///
  protocolError,

  /// The TLS Handshake failed
  tlsHandshake,

  /// A received data frame was to large. (`1009`, WebRtc)
  ///
  /// It's very unlikely to happen with WebRtc, but one possible way
  /// could be if the task data shipped with an `auth` message became
  /// way to big.
  messageToBig,

  /// Any other unexpected status code.
  ///
  /// This includes following status codes, which all shouldn't happen
  /// (at least in our use case):
  ///
  /// - `1005`: No Status Received
  /// - `1008`: Policy violation
  /// - `1010`: Missing Extension
  /// - `1014`: Bad Gateway
  other
}

/// A unexpected error occurred.
///
/// This is most likely a bug on at least one side, but in rare cases can also
/// be caused by bad `pingInterval` settings and/or unusual network conditions.
///
/// Retrying is likely not going to help, through it might be worth to retry
/// a single time with a larger time gap in case of internal error and
/// other times after a huge time gap as the server might be fixed by then.
@immutable
class UnexpectedStatus extends Event {
  final UnexpectedStatusVariant variant;
  final int closeCode;

  // Creates a instance, it doesn't check if `variant` matches `closeCode`.
  //
  // Preferably use `eventFromStatus` instead.
  UnexpectedStatus.unchecked(
    this.variant,
    this.closeCode,
  );

  @override
  List<Object?> get props => [variant, closeCode];
}

/// TODO: What exactly is this? It's currently unused? Or not?
@immutable
class HandoverOfSignalingChannel extends Event {}

/// Event indicating that the web socket was closed.
///
/// This doesn't contain a specific reason as there could be multiple reasons,
/// or no reason in case of a normal closing and appropriate events for this
/// reasons will already have been emitted.
///
/// In a certain way this is a "end of stream" marker.
@immutable
class Closed extends Event {}

/// Creates a event from an status code.
///
/// This can be used with WebRtc on-close status codes or codes send with a
/// `close` message, because of that this will not create `Closed` events.
/// This also means that a non (direct) error close code will not create an
/// event (`normal` and `goingAway`).
///
Event? eventFromStatus(int closeCode) {
  switch (closeCode) {
    case 1000:
    case 1001:
      return null;
    case 1002:
    case 1003:
    case 1007:
    case 3001:
      return UnexpectedStatus.unchecked(
          UnexpectedStatusVariant.protocolError, closeCode);
    case 1006:
      return LikelyTemporaryFailure(TempFailureVariant.abnormalClosure);
    case 1009:
      return UnexpectedStatus.unchecked(
          UnexpectedStatusVariant.messageToBig, closeCode);
    case 1011:
    case 3002:
      return UnexpectedStatus.unchecked(
          UnexpectedStatusVariant.internalError, closeCode);
    case 1012:
      return LikelyTemporaryFailure(TempFailureVariant.serviceRestart);
    case 1013:
      return LikelyTemporaryFailure(TempFailureVariant.tryAgainLater);
    case 1015:
      return UnexpectedStatus.unchecked(
          UnexpectedStatusVariant.tlsHandshake, closeCode);
    case 3000:
      return LikelyTemporaryFailure(TempFailureVariant.pathFull);
    case 3003:
      return HandoverOfSignalingChannel();
    case 3004:
      return LikelyTemporaryFailure(TempFailureVariant.droppedByInitiator);
    case 3005:
      return InitiatorCouldNotDecrypt();
    case 3006:
      return NoSharedTaskFound();
    case 3007:
      return IncompatibleServerKey();
    case 3008:
      return LikelyTemporaryFailure(TempFailureVariant.timeout);
    default:
      return UnexpectedStatus.unchecked(
          UnexpectedStatusVariant.other, closeCode);
  }
}
