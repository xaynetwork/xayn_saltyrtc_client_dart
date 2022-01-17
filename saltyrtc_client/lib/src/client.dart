// Copyright 2021 Xayn AG
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:async' show StreamController;
import 'dart:typed_data' show Uint8List;

import 'package:meta/meta.dart' show protected;
import 'package:xayn_saltyrtc_client/events.dart' show Event;
import 'package:xayn_saltyrtc_client/src/crypto/crypto.dart'
    show Crypto, KeyStore, AuthToken, InitialClientAuthMethod;
import 'package:xayn_saltyrtc_client/src/logger.dart' show logger;
import 'package:xayn_saltyrtc_client/src/messages/close_code.dart'
    show CloseCode;
import 'package:xayn_saltyrtc_client/src/protocol/network.dart' show WebSocket;
import 'package:xayn_saltyrtc_client/src/protocol/phases/phase.dart'
    show InitialCommon, InitiatorConfig, Phase, ResponderConfig;
import 'package:xayn_saltyrtc_client/src/protocol/phases/server_handshake.dart'
    show InitiatorServerHandshakePhase, ResponderServerHandshakePhase;
import 'package:xayn_saltyrtc_client/src/protocol/task.dart' show TaskBuilder;

extension BytesToAuthToken on Uint8List {
  AuthToken toAuthToken(Crypto crypto) =>
      crypto.createAuthTokenFromToken(token: this);
}

abstract class Client {
  final WebSocket _ws;
  final StreamController<Event> _events;
  Phase _phase;
  bool _hasStarted = false;

  @protected
  Client(this._ws, this._phase, this._events);

  /// Runs this Client returning a stream of events indicating the progress.
  Stream<Event> run() {
    if (_hasStarted) {
      throw StateError('SaltyRtc Client is already running');
    }
    // We must only access the phase from the run loop.
    _hasStarted = true;
    _run();
    return _events.stream;
  }

  Future<void> _run() async {
    try {
      await for (final message in _ws.stream) {
        if (_phase.isClosingWsStream) {
          // Can happen as closing the sink doesn't drop any pending incoming
          // messages, isClosing SHOULD only be true after `doClose` was called
          // on the `Phase`.
          logger.w('phase received message after closing');
          break;
        }
        _phase = _phase.handleMessage(message);
      }
    } catch (e, s) {
      _phase.killBecauseOf(e, s);
    } finally {
      _phase.notifyWsStreamClosed();
    }
  }

  /// Closes the client and disconnect from the server canceling any ongoing
  /// task.
  ///
  /// This can be freely called from any async task.
  void cancel() {
    _phase.close(CloseCode.goingAway, 'cancel');
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
      throw ArgumentError(
        'One between responder trusted key or authentication token is needed',
      );
    }
    if (responderTrustedKey != null && sharedAuthToken != null) {
      throw ArgumentError(
        'Only one between responder trusted key or authentication token is needed.'
        'Authentication token must be used only once.',
      );
    }

    final events = StreamController<Event>.broadcast();
    final common = InitialCommon(crypto, ws, events.sink);
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
    final common = InitialCommon(crypto, ws, events.sink);

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
