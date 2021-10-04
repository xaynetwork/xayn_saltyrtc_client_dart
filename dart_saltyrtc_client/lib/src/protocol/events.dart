import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/src/logger.dart' show logger;
import 'package:equatable/equatable.dart' show Equatable;
import 'package:meta/meta.dart' show immutable;

abstract class Event extends Equatable {
  @override
  List<Object?> get props => [];
}

/// An event which will lead to the SaltyRtc client being closed.
abstract class ClosingErrorEvent extends Event {}

/// An event which can't be recovered from without a software update (somewhere).
///
/// Through the software which might need updating might be the other devices
/// app or the server (in case of a messed up public key update).
///
/// Be aware that `UnexpectedStatus` and `InternalError` only implement
/// `ClosingErrorEvent` but could very well be a `FatalErrorEvent`
/// but we can't really tell.
///
abstract class FatalErrorEvent extends ClosingErrorEvent {}

@immutable
class ServerHandshakeDone extends Event {}

@immutable
class ResponderAuthenticated extends Event {
  /// Permanent key of the responder.
  /// After this has been received the authentication token must not
  /// be used again, this key must be use instead.
  ///
  /// But be aware that the responder might not yet be aware of being
  /// authenticated.
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
/// Be aware that receiving a disconnected (known peer) event implies that
/// the connection was reset to the begin of the client to client handshake,
/// it doesn't imply that the connection will be closed.
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
///
/// Be aware that receiving a send error (of which the peer had been
/// authenticated) event implies that the connection was reset to the begin of
/// the client to client handshake, it doesn't imply that the connection
/// will be closed.
@immutable
class SendError extends Event {
  /// True if we already completed the client to client handshake.
  final bool wasAuthenticated;

  SendError({required this.wasAuthenticated});
}

/// No shared task was found between the initiator and responder.
///
/// This means that both clients are incompatible, which might be fixed
/// through a software update. Or might mean that two unrelated applications
/// try to accidentally connect with each other.
@immutable
class NoSharedTaskFound extends FatalErrorEvent {}

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
@immutable
class InitiatorCouldNotDecrypt extends FatalErrorEvent {}

/// The key we expect the server to use is not a key the server has.
@immutable
class IncompatibleServerKey extends FatalErrorEvent {}

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
class LikelyTemporaryFailure extends ClosingErrorEvent {
  final TempFailureVariant variant;

  LikelyTemporaryFailure(this.variant);

  @override
  List<Object?> get props => [variant];
}

enum UnexpectedStatusVariant {
  /// The server or other client ran into a internal error.
  ///
  /// *If we run into an internalError we use the InternalError event,
  ///  which provides additional debug information.*
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
  messageTooBig,

  /// Any other unexpected status code.
  ///
  /// This includes following status codes, which all shouldn't happen
  /// (at least in our use case):
  ///
  /// - `1005`: No Status Received
  /// - `1008`: Policy violation
  /// - `1010`: Missing Extension
  /// - `1014`: Bad Gateway
  /// - ...
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
///
/// **If a `UnexpectedStatus` error repeats to appear then it should be
/// treated like a `FatalErrorEvent`**
@immutable
class UnexpectedStatus extends ClosingErrorEvent {
  final UnexpectedStatusVariant variant;
  final int? closeCode;

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

/// A unexpected exception was thrown, this error is 100% indicating that we hit a bug.
@immutable
class InternalError extends ClosingErrorEvent {
  final Object error;

  InternalError(this.error);
}

/// Creates a event from an status code.
///
/// This can be used with WebRtc on-close status codes or codes send with a
/// `close` message, because of that this will not create `Closed` events.
/// This also means that a non (direct) error close code will not create an
/// event (`normal` and `goingAway`).
///
Event? eventFromWSCloseCode(int? closeCode) {
  if (closeCode == null) {
    logger.e('unexpectedly received no closeCode');
    return UnexpectedStatus.unchecked(UnexpectedStatusVariant.other, closeCode);
  }
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
          UnexpectedStatusVariant.messageTooBig, closeCode);
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
    // case 3003:
    //   return HandoverOfSignalingChannel();
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
