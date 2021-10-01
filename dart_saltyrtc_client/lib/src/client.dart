import 'dart:async' show StreamController;
import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/src/crypto/crypto.dart'
    show Crypto, KeyStore, AuthToken, InitialClientAuthMethod;
import 'package:dart_saltyrtc_client/src/messages/close_code.dart'
    show CloseCode, CloseCodeToFromInt;
import 'package:dart_saltyrtc_client/src/protocol/error.dart'
    show SaltyRtcError;
import 'package:dart_saltyrtc_client/src/protocol/events.dart' show Event;
import 'package:dart_saltyrtc_client/src/protocol/network.dart' show WebSocket;
import 'package:dart_saltyrtc_client/src/protocol/phases/phase.dart'
    show Phase, Common, InitiatorConfig, ResponderConfig;
import 'package:dart_saltyrtc_client/src/protocol/phases/server_handshake.dart'
    show InitiatorServerHandshakePhase, ResponderServerHandshakePhase;
import 'package:dart_saltyrtc_client/src/protocol/task.dart' show Task;
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

  Stream<Event> get events => _events.stream;

  void run() {
    if (_state == _ClientState.running) {
      throw SaltyRtcClientError('SaltyRtc Client is already running');
    }

    _state = _ClientState.running;

    _ws.stream.forEach((bytes) {
      _onWsMessage(bytes);
    }).whenComplete(() {
      _close();
    });
  }

  /// Actions to do always when we close the client.
  Future<void> _close() async {
    // TODO we need to send a close event before closing the stream.
    await _events.close();
  }

  Future<void> close() async {
    return _ws.sink.close(CloseCode.closingNormal.toInt(), '');
  }

  void _onWsMessage(Uint8List bytes) {
    try {
      _phase = _phase.handleMessage(bytes);
    } on SaltyRtcError catch (e, s) {
      _closeAndThrow(e.closeCode, e, s);
    } catch (e, s) {
      _closeAndThrow(CloseCode.internalError, e, s);
    }
  }

  /// Close the web socket connection and raise and exception for the client.
  void _closeAndThrow(CloseCode closeCode, Object error, StackTrace st) {
    _ws.sink.close(closeCode.toInt(), '');
    throw SaltyRtcClientError(error.toString(), st);
  }
}

class InitiatorClient extends Client {
  InitiatorClient._(WebSocket ws, Phase phase, StreamController<Event> events)
      : super(ws, phase, events);

  factory InitiatorClient.build(
    Crypto crypto,
    WebSocket ws,
    KeyStore ourPermanentKeys,
    List<Task> tasks, {
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
    final common = Common(
      crypto,
      ws.sink,
      events.sink,
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
    List<Task> tasks, {
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
