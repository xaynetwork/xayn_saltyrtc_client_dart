import 'dart:async' show StreamController;
import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/src/crypto/crypto.dart'
    show Crypto, KeyStore, AuthToken, InitialClientAuthMethod;
import 'package:dart_saltyrtc_client/src/logger.dart' show logger;
import 'package:dart_saltyrtc_client/src/messages/close_code.dart'
    show CloseCode, CloseCodeToFromInt;
import 'package:dart_saltyrtc_client/src/protocol/events.dart'
    show Event, InternalError, eventFromWSCloseCode;
import 'package:dart_saltyrtc_client/src/protocol/network.dart' show WebSocket;
import 'package:dart_saltyrtc_client/src/protocol/phases/phase.dart'
    show Common, InitiatorConfig, Phase, ResponderConfig;
import 'package:dart_saltyrtc_client/src/protocol/phases/server_handshake.dart'
    show InitiatorServerHandshakePhase, ResponderServerHandshakePhase;
import 'package:dart_saltyrtc_client/src/protocol/task.dart' show TaskBuilder;
import 'package:dart_saltyrtc_client/src/utils.dart' show EmitEventExt;
import 'package:meta/meta.dart' show immutable, protected;

enum _ClientState {
  initialized,
  running,
}

extension BytesToAuthToken on Uint8List {
  AuthToken toAuthToken(Crypto crypto) =>
      crypto.createAuthTokenFromToken(token: this);
}

abstract class Client {
  final WebSocket _ws;
  final StreamController<Event> _events;
  Phase _phase;
  _ClientState _state = _ClientState.initialized;

  @protected
  Client(this._ws, this._phase, this._events);

  /// Runs this Client returning a stream of events indicating the progress.
  Stream<Event> run() {
    if (_state == _ClientState.running) {
      throw SaltyRtcClientError('SaltyRtc Client is already running');
    }

    _state = _ClientState.running;

    // Spawn run, run will add events to the stream and
    // will close the stream once it ends.
    _run();
    return _events.stream;
  }

  Future<void> _run() async {
    try {
      await for (final message in _ws.stream) {
        _onWsMessage(message);
      }
      final event = eventFromWSCloseCode(_ws.closeCode);
      if (event != null) {
        _events.sink.emitEvent(event);
      }
    } catch (e, s) {
      _events.sink.emitEvent(InternalError(e), s);
      await _closeWsSink(CloseCode.internalError, 'Internal Error: $e\n$s');
    } finally {
      await _events.close();
    }
  }

  void _onWsMessage(Uint8List bytes) {
    if (_phase.isClosed) {
      logger.e('phase received message after closing');
      return;
    }
    _phase = _phase.handleMessage(bytes);
    if (_phase.isClosed) {
      _closeWsSink(_phase.closeCode, _phase.closeReason);
    }
  }

  Future<void> _closeWsSink(CloseCode? closeCode, String? reason) {
    logger.i('closing SaltyRtc connection (code=$closeCode): $reason');
    return _ws.sink.close(closeCode?.toInt(), '');
  }

  Future<void> close() async {
    await _closeWsSink(CloseCode.goingAway, 'Client.close called');
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

    final eventsCtrl = StreamController<Event>.broadcast();
    final common = Common(
      crypto,
      ws.sink,
      eventsCtrl.sink,
    );
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

    return InitiatorClient._(ws, phase, eventsCtrl);
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
    final common = Common(
      crypto,
      ws.sink,
      events.sink,
    );

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
