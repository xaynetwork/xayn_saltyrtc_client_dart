import 'dart:typed_data' show Uint8List;

import 'package:equatable/equatable.dart' show Equatable;
import 'package:meta/meta.dart' show immutable;

/*
  WARNING: This file is fully re-exported, it should only contain event
  definitions and nothing else.
*/

/// Event base class.
abstract class Event extends Equatable {
  @override
  List<Object?> get props => [];
}

/// An event which will lead to the SaltyRtc client being closed.
///
/// Emitting a event which is a subtype of this type will add it to
/// the stream using `addError` which means it will throw and exception
/// if you listen on the stream using `await for(...)`. Or it will trigger
/// the error handler if you don't use async.
abstract class ClosingErrorEvent extends Event implements Exception {}

/// An error which can't be recovered from.
///
/// If an error of this kind is received also all future connections with the
/// same configuration of this client, the server and the peer will fail
/// with this error.
///
/// Be aware that `UnexpectedStatus` and `InternalError` only implement
/// `ClosingErrorEvent` but could very well be a `FatalErrorEvent`
/// but we can't really tell.
///
abstract class FatalErrorEvent extends ClosingErrorEvent {}

/// Event emitted when the server client to handshake completed.
@immutable
class ServerHandshakeDone extends Event {}

/// Event emitted when the client to client handshake completed.
///
/// This is useful during the initial peering of two clients as
/// it will contains the public key of the responder (which the
/// initiator would need to remember to allow a repairing without
/// an auth token).
///
/// For consistency this is emitted by both the initiator and responder,
/// it always contains the public key of the responder no matter what kind
/// of client emitted it.
@immutable
class ResponderAuthenticated extends Event {
  /// Permanent key of the responder.
  ///
  /// After this has been received the auth token must not
  /// be used again, this key must be use instead.
  ///
  /// But be aware that the responder might not yet be aware of being
  /// authenticated.
  final Uint8List permanentKey;

  ResponderAuthenticated(this.permanentKey);

  @override
  List<Object?> get props => [permanentKey];
}

/// Events produced by "additional" responders on the path.
///
/// If we have a successfully started client to client handshake or are in
/// the task phase then events produced by other responders will be wrapped
/// into this type.
///
/// Besides for some statistics around e.g. spam or DoS attacks or people
/// scanning QR codes multiple times this events have not much use.
///
@immutable
class AdditionalResponderEvent extends Event {
  final Event event;

  AdditionalResponderEvent(this.event);

  @override
  List<Object?> get props => event.props;
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
class PeerDisconnected extends Event {
  final PeerKind peerKind;

  PeerDisconnected(this.peerKind);

  @override
  List<Object?> get props => [peerKind];
}

enum PeerKind {
  /// A peer which has not yet fully completed the authentication process.
  ///
  unauthenticated,

  /// A peer with which we completed a client to client handshake.
  authenticated,
}

/// Event emitted when sending a message to a client failed.
///
/// Be aware that receiving a send error (of which the peer had been
/// authenticated) event implies that the connection was reset to the begin of
/// the client to client handshake, it doesn't imply that the connection
/// will be closed.
@immutable
class SendingMessageToPeerFailed extends Event {
  /// True if we already completed the client to client handshake.
  final PeerKind peerKind;

  SendingMessageToPeerFailed(this.peerKind);

  @override
  List<Object?> get props => [peerKind];
}

/// No shared task was found between the initiator and responder.
///
/// This means that the clients are incompatible and they do not have a common
/// task that can be used to communicate between them.
@immutable
class NoSharedTaskFound extends FatalErrorEvent {}

/// Event indicating that the initiator could not decrypt the message sent from us.
///
/// This is only produced by responder clients during the client to client
/// handshake.
///
/// This mainly happens in following situations:
///
/// - The wrong auth token is used.
/// - An auth token was required but not used.
/// - An auth token was not required but send.
/// - The responders permanent key doesn't match the expected
///   trusted responders key.
///
/// Some (but not all) potential situations in which this can happen are:
///
/// - The responder did disconnected during a previous handshake
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

  /// The WebSocket connection was closed without sending a close frame.
  ///
  /// This can happen in case of TCP realizing the connection
  /// to the server is gone, it's inherently similar to `timeout`.
  ///
  /// While this is not part of the SaltyRtc protocol it can happen anyway.
  abnormalClosure,

  /// 253 responders are currently connected to the server on given path.
  pathFull,

  /// The initiator dropped us.
  ///
  /// This mainly happens if the responder tries to connect to a path and is
  /// are dropped as part of the path cleaning.
  ///
  /// It also could happen if the initiator is already peered, which should only
  /// happen if somehow multiple devices got the same auth token, e.g. by
  /// scanning the same QR code. We can not differentiate this case from the
  /// other case.
  ///
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
  /// The server or other client ran into an internal error.
  ///
  /// *If we run into an internalError we use the InternalError event,
  ///  which provides additional debug information.*
  ///
  /// Either `1011` (WebSocket) or `3002` SaltyRtc.
  internalError,

  /// The server or other client found we breached to protocol.
  ///
  /// This can be a
  ///
  /// - `1002`: WebSocket protocol error
  /// - `1003`: WebSocket unsupported data (should have been `3001`)
  /// - `1007`: WebSocket invalid frame payload data (should have been `3001`)
  /// - `3001`: SaltyRtc protocol error
  ///
  protocolError,

  /// The TLS Handshake failed
  tlsHandshake,

  /// A received data frame was to large.
  ///
  /// This could happen if the task data shipped with an `auth` message is
  /// too big, or if a task send to much data in one message.
  messageTooBig,

  /// Any other unexpected status code.
  ///
  other
}

/// An unexpected error occurred.
///
/// This is most likely a bug on at least one side, but in rare cases can also
/// be caused by bad settings and/or unusual network conditions.
///
@immutable
class UnexpectedStatus extends ClosingErrorEvent {
  final UnexpectedStatusVariant variant;
  final int? closeCode;

  // Creates an instance, it doesn't check if `variant` matches `closeCode`.
  //
  // Preferably use `eventFromStatus` instead.
  UnexpectedStatus.unchecked(
    this.variant,
    this.closeCode,
  );

  @override
  List<Object?> get props => [variant, closeCode];
}

/// An unexpected exception was thrown, this error is 100% indicating that we hit a bug.
@immutable
class InternalError extends ClosingErrorEvent {
  final Object error;

  InternalError(this.error);
}

/// Protocol Error with the Server
///
@immutable
class ProtocolErrorWithServer extends ClosingErrorEvent {}

/// Protocol Error with peer.
@immutable
class ProtocolErrorWithPeer extends Event {
  final PeerKind peerKind;

  ProtocolErrorWithPeer(this.peerKind);

  @override
  List<Object?> get props => [peerKind];
}

/// Event emitted when all responsibility is handed over to the task and the
/// original WebSocket is closed because it's no longer needed.
@immutable
class HandoverToTask extends Event {}
