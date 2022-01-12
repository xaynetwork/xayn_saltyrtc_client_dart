// Copyright 2021 Xayn AG
//
// Licensed under the Apache License, Version 2.0 (the License);
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:typed_data' show Uint8List;

import 'package:hex/hex.dart' show HEX;
import 'package:web_socket_channel/web_socket_channel.dart'
    show WebSocketChannel;
import 'package:xayn_flutter_saltyrtc_client/src/crypto/crypto_provider.dart'
    show getCrypto;
import 'package:xayn_flutter_saltyrtc_client/src/network.dart' show WebSocket;
import 'package:xayn_saltyrtc_client/crypto.dart' show KeyStore;
import 'package:xayn_saltyrtc_client/events.dart' show Event;
import 'package:xayn_saltyrtc_client/xayn_saltyrtc_client.dart' as saltyrtc
    show InitiatorClient, ResponderClient;
import 'package:xayn_saltyrtc_client/xayn_saltyrtc_client.dart'
    show websocketProtocols, TaskBuilder, saltyRtcClientLibLogger;

abstract class SaltyRtcClient {
  /// The identity of this client
  Identity get identity;

  /// Start the SaltyRtc client returning a stream of events about it's state.
  Stream<Event> run();

  /// Close the connection with the server, the client is not usable after
  /// this method has been called.
  void cancel();
}

class Identity {
  final KeyStore _permanentKeyPair;

  Identity._(this._permanentKeyPair);

  static Future<Identity> fromRawKeys({
    required Uint8List publicKey,
    required Uint8List privateKey,
  }) async {
    final crypto = await getCrypto();
    final keyStore = crypto.createKeyStoreFromKeys(
      privateKey: privateKey.sublist(0),
      publicKey: publicKey.sublist(0),
    );
    return Identity._(keyStore);
  }

  static Future<Identity> newIdentity() async {
    final crypto = await getCrypto();
    return Identity._(crypto.createKeyStore());
  }

  Uint8List getPrivateKey() => _permanentKeyPair.privateKey.sublist(0);
  Uint8List getPublicKey() => _permanentKeyPair.publicKey.sublist(0);
}

/// Client for an initiator.
class InitiatorClient implements SaltyRtcClient, saltyrtc.InitiatorClient {
  /// Creates a fresh authentication token.
  ///
  /// It should only be used once to peer two clients, but once the peering
  /// is done or restarted from scratch (instead of just retried due to, e.g.
  /// network problems) it should no longer be used.
  static Future<Uint8List> createAuthToken() async {
    final crypto = await getCrypto();
    final token = crypto.createAuthToken();
    return token.bytes;
  }

  @override
  final Identity identity;
  final saltyrtc.InitiatorClient _client;

  InitiatorClient._(this.identity, this._client);

  /// Create an initiator that needs to communicate with a responder that has
  /// not yet been authenticated. The some authentication token must be used only
  /// once. If an errors occurs before the selection of a task is completed a
  /// different value for `sharedAuthToken` must be passed.
  static Future<InitiatorClient> withUntrustedResponder(
    Uri baseUri,
    List<TaskBuilder> tasks, {
    required Uint8List expectedServerKey,
    required Uint8List sharedAuthToken,
    int? pingInterval,
    Identity? identity,
  }) {
    return InitiatorClient._build(
      baseUri,
      tasks,
      pingInterval: pingInterval,
      expectedServerKey: expectedServerKey,
      sharedAuthToken: sharedAuthToken,
      identity: identity,
    );
  }

  /// Create an initiator that needs to communicate with a responder
  /// that is considered trusted and that.
  static Future<InitiatorClient> withTrustedResponder(
    Uri baseUri,
    List<TaskBuilder> tasks, {
    required Uint8List expectedServerKey,
    required Uint8List responderTrustedKey,
    int? pingInterval,
    Identity? identity,
  }) {
    return InitiatorClient._build(
      baseUri,
      tasks,
      pingInterval: pingInterval,
      expectedServerKey: expectedServerKey,
      identity: identity,
    );
  }

  static Future<InitiatorClient> _build(
    Uri baseUri,
    List<TaskBuilder> tasks, {
    required Uint8List expectedServerKey,
    Uint8List? responderTrustedKey,
    Uint8List? sharedAuthToken,
    Identity? identity,
    int? pingInterval,
  }) async {
    final crypto = await getCrypto();
    identity ??= Identity._(crypto.createKeyStore());
    pingInterval ??= 0;
    final uri = _getUri(baseUri, identity._permanentKeyPair.publicKey);
    saltyRtcClientLibLogger.i('connecting as initiator to uri: $uri');
    final client = saltyrtc.InitiatorClient.build(
      // we get a KeyStore that can only be created from a Crypto
      // so it is already initialized
      crypto,
      WebSocket(
        WebSocketChannel.connect(
          uri,
          protocols: websocketProtocols,
        ),
      ),
      identity._permanentKeyPair,
      tasks,
      pingInterval: pingInterval,
      expectedServerKey: expectedServerKey,
      responderTrustedKey: responderTrustedKey,
      sharedAuthToken: sharedAuthToken,
    );

    return InitiatorClient._(identity, client);
  }

  /// Starts the SaltyRtc client returning a stream of events about it's state.
  @override
  Stream<Event> run() => _client.run();

  /// Close the connection with the server, the client is not usable after
  /// this method has been called.
  @override
  void cancel() {
    _client.cancel();
  }
}

/// Client for an responder
class ResponderClient implements SaltyRtcClient, saltyrtc.ResponderClient {
  @override
  final Identity identity;
  final saltyrtc.ResponderClient _client;

  ResponderClient._(this.identity, this._client);

  /// Create a responder that needs to authenticate itself with the initiator
  /// using the authentication token. The some authentication token must be used only
  /// once. If an errors accurs before the selection of a task is completed a
  /// different value for `sharedAuthToken` must be passed.
  static Future<ResponderClient> withAuthToken(
    Uri baseUri,
    List<TaskBuilder> tasks, {
    required Uint8List expectedServerKey,
    required Uint8List initiatorTrustedKey,
    required Uint8List sharedAuthToken,
    Identity? identity,
    int? pingInterval,
  }) {
    return ResponderClient._build(
      baseUri,
      tasks,
      pingInterval: pingInterval,
      expectedServerKey: expectedServerKey,
      initiatorTrustedKey: initiatorTrustedKey,
      sharedAuthToken: sharedAuthToken,
      identity: identity,
    );
  }

  /// Create an responder that has already authenticated itself with the initiator.
  static Future<ResponderClient> withTrustedKey(
    Uri baseUri,
    List<TaskBuilder> tasks, {
    required Uint8List expectedServerKey,
    required Uint8List initiatorTrustedKey,
    int? pingInterval,
    Identity? identity,
  }) {
    return ResponderClient._build(
      baseUri,
      tasks,
      pingInterval: pingInterval,
      expectedServerKey: expectedServerKey,
      initiatorTrustedKey: initiatorTrustedKey,
      identity: identity,
    );
  }

  static Future<ResponderClient> _build(
    Uri baseUri,
    List<TaskBuilder> tasks, {
    required Uint8List expectedServerKey,
    required Uint8List initiatorTrustedKey,
    int? pingInterval,
    Uint8List? sharedAuthToken,
    Identity? identity,
  }) async {
    final crypto = await getCrypto();
    identity ??= Identity._(crypto.createKeyStore());
    pingInterval ??= 0;
    final uri = _getUri(baseUri, initiatorTrustedKey);
    saltyRtcClientLibLogger.i('connecting as responder to uri: $uri');
    final client = saltyrtc.ResponderClient.build(
      crypto,
      WebSocket(
        WebSocketChannel.connect(
          uri,
          protocols: websocketProtocols,
        ),
      ),
      identity._permanentKeyPair,
      tasks,
      pingInterval: pingInterval,
      expectedServerKey: expectedServerKey,
      initiatorTrustedKey: initiatorTrustedKey,
      sharedAuthToken: sharedAuthToken,
    );

    return ResponderClient._(identity, client);
  }

  /// Start the SaltyRtc client returning a stream of events about it's state.
  @override
  Stream<Event> run() => _client.run();

  /// Close the connection with the server, the client is not
  /// usable after this method has been called.
  @override
  void cancel() {
    _client.cancel();
  }
}

/// Construct the uri where the last part of the path is the public of the initiator.
Uri _getUri(Uri baseUri, Uint8List initiatorPublicKey) {
  return baseUri.replace(
    // we keep the original path because the server can be deployed behind a specific endpoint
    path: '${baseUri.path}/${HEX.encode(initiatorPublicKey)}',
    query: null,
    fragment: null,
  );
}
