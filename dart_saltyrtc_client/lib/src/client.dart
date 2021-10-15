import 'dart:async' show StreamController;
import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/src/closer.dart' show Closer;
import 'package:dart_saltyrtc_client/src/crypto/crypto.dart'
    show Crypto, KeyStore, AuthToken, InitialClientAuthMethod;
import 'package:dart_saltyrtc_client/src/logger.dart' show logger;
import 'package:dart_saltyrtc_client/src/messages/close_code.dart'
    show CloseCode;
import 'package:dart_saltyrtc_client/src/protocol/events.dart'
    show Event, InternalError;
import 'package:dart_saltyrtc_client/src/protocol/network.dart' show WebSocket;
import 'package:dart_saltyrtc_client/src/protocol/phases/phase.dart'
    show InitialCommon, InitiatorConfig, Phase, ResponderConfig;
import 'package:dart_saltyrtc_client/src/protocol/phases/server_handshake.dart'
    show InitiatorServerHandshakePhase, ResponderServerHandshakePhase;
import 'package:dart_saltyrtc_client/src/protocol/task.dart' show TaskBuilder;
import 'package:dart_saltyrtc_client/src/utils.dart' show EmitEventExt;
import 'package:meta/meta.dart' show immutable, protected;

extension BytesToAuthToken on Uint8List {
  AuthToken toAuthToken(Crypto crypto) =>
      crypto.createAuthTokenFromToken(token: this);
}

abstract class Client {
  final WebSocket _ws;
  final StreamController<Event> _events;
  final Closer _closer;
  Phase? _phase;

  @protected
  Client(this._ws, Phase this._phase, this._events)
      : _closer = _phase.common.closer;

  /// Runs this Client returning a stream of events indicating the progress.
  Stream<Event> run() {
    final phase = _phase;
    if (phase == null) {
      throw SaltyRtcClientError('SaltyRtc Client is already running');
    }
    // We must only access the phase from the run loop.
    _phase = null;
    _run(phase);
    return _events.stream;
  }

  Future<void> _run(Phase phase) async {
    try {
      await for (final message in _ws.stream) {
        if (_closer.isClosing) {
          // Can happen as closing the sink doesn't drop any pending incoming
          // messages, isClosing SHOULD only be true after `doClose` was called
          // on the `Phase`.
          logger.w('phase received message after closing');
          break;
        }
        phase = phase.handleMessage(message);
      }
    } catch (e, s) {
      _events.sink.emitEvent(InternalError(e), s);
      _closer.close(CloseCode.internalError, e.toString());
    } finally {
      _closer.notifyConnectionClosed();
    }
  }

  /// Closes the client and disconnect from the server canceling any ongoing
  /// task.
  Future<void> cancel() {
    _closer.close(CloseCode.goingAway, 'cancel');
    return _closer.onClosed;
  }
}

class InitiatorClient extends Client {
  InitiatorClient._(WebSocket ws, Phase phase, StreamController<Event> events)
      : super(ws, phase, events);

  factory InitiatorClient.build(
    Crypto crypto,
    WebSocket ws,
    KeyStore ourPermanentKeys,
    List<TaskBuilder> tasks, {
    required int pingInterval,
    required Uint8List expectedServerKey,
    Uint8List? responderTrustedKey,
    Uint8List? sharedAuthToken,
  }) {
    if (responderTrustedKey == null && sharedAuthToken == null) {
      throw SaltyRtcClientError(
        'One between responder trusted key or authentication token is needed',
      );
    }
    if (responderTrustedKey != null && sharedAuthToken != null) {
      throw SaltyRtcClientError(
        'Only one between responder trusted key or authentication token is needed.'
        'Authentication token must be used only once.',
      );
    }

    final events = StreamController<Event>.broadcast();
    final common = InitialCommon(crypto, ws.sink, events.sink, Closer(ws));
    final authMethod = InitialClientAuthMethod.fromEither(
      crypto: crypto,
      authToken: sharedAuthToken?.toAuthToken(crypto),
      trustedResponderPermanentPublicKey: responderTrustedKey,
      initiatorPermanentKeys: ourPermanentKeys,
    );
    final config = InitiatorConfig(
      authMethod: authMethod,
      permanentKeys: ourPermanentKeys,
      tasks: tasks,
      pingInterval: pingInterval,
      expectedServerPublicKey: expectedServerKey,
    );
    final phase = InitiatorServerHandshakePhase(common, config);

    return InitiatorClient._(ws, phase, events);
  }
}

class ResponderClient extends Client {
  ResponderClient._(WebSocket ws, Phase phase, StreamController<Event> events)
      : super(ws, phase, events);

  factory ResponderClient.build(
    Crypto crypto,
    WebSocket ws,
    KeyStore ourPermanentKeys,
    List<TaskBuilder> tasks, {
    required int pingInterval,
    required Uint8List expectedServerKey,
    required Uint8List initiatorTrustedKey,
    Uint8List? sharedAuthToken,
  }) {
    final events = StreamController<Event>.broadcast();
    final common = InitialCommon(crypto, ws.sink, events.sink, Closer(ws));

    final config = ResponderConfig(
      permanentKeys: ourPermanentKeys,
      tasks: tasks,
      initiatorPermanentPublicKey: initiatorTrustedKey,
      pingInterval: pingInterval,
      expectedServerPublicKey: expectedServerKey,
      authToken: sharedAuthToken?.toAuthToken(crypto),
    );
    final phase = ResponderServerHandshakePhase(
      common,
      config,
    );

    return ResponderClient._(ws, phase, events);
  }
}

@immutable
class SaltyRtcClientError extends Error {
  final String message;
  final StackTrace? _customStackTrace;

  @override
  StackTrace? get stackTrace => _customStackTrace ?? super.stackTrace;

  SaltyRtcClientError(this.message, [this._customStackTrace]);
}
