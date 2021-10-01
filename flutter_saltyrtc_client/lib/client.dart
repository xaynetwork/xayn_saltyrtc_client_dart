import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/dart_saltyrtc_client.dart' as saltyrtc
    show
        InitiatorClient,
        ResponderClient,
        websocketProtocols,
        KeyStore,
        TaskBuilder;
import 'package:dart_saltyrtc_client/src/protocol/events.dart' show Event;
import 'package:flutter_saltyrtc_client/crypto/crypto_provider.dart'
    show crypto;
import 'package:flutter_saltyrtc_client/network.dart' show WebSocket;
import 'package:hex/hex.dart' show HEX;
import 'package:web_socket_channel/web_socket_channel.dart'
    show WebSocketChannel;

/// Client for an initiator
class InitiatorClient implements saltyrtc.InitiatorClient {
  final saltyrtc.InitiatorClient _client;

  InitiatorClient._(this._client);

  factory InitiatorClient.withUntrustedResponder(
    Uri baseUri,
    saltyrtc.KeyStore ourPermanentKeys,
    List<saltyrtc.TaskBuilder> tasks, {
    required int pingInterval,
    required Uint8List expectedServerKey,
    required Uint8List sharedAuthToken,
  }) {
    return InitiatorClient._build(
      baseUri,
      ourPermanentKeys,
      tasks,
      pingInterval: pingInterval,
      expectedServerKey: expectedServerKey,
      sharedAuthToken: sharedAuthToken,
    );
  }

  factory InitiatorClient.withTrustedResponder(
    Uri baseUri,
    saltyrtc.KeyStore ourPermanentKeys,
    List<saltyrtc.TaskBuilder> tasks, {
    required int pingInterval,
    required Uint8List expectedServerKey,
    required Uint8List responderTrustedKey,
  }) {
    return InitiatorClient._build(
      baseUri,
      ourPermanentKeys,
      tasks,
      pingInterval: pingInterval,
      expectedServerKey: expectedServerKey,
    );
  }

  factory InitiatorClient._build(
    Uri baseUri,
    saltyrtc.KeyStore ourPermanentKeys,
    List<saltyrtc.TaskBuilder> tasks, {
    required int pingInterval,
    required Uint8List expectedServerKey,
    Uint8List? responderTrustedKey,
    Uint8List? sharedAuthToken,
  }) {
    final uri = _getUri(baseUri, ourPermanentKeys.publicKey);
    final client = saltyrtc.InitiatorClient.build(
      // we get a KeyStore that can only be created from a Crypto
      // so it is already initialized
      crypto(),
      WebSocket(WebSocketChannel.connect(
        uri,
        protocols: saltyrtc.websocketProtocols,
      )),
      ourPermanentKeys,
      tasks,
      pingInterval: pingInterval,
      expectedServerKey: expectedServerKey,
      responderTrustedKey: responderTrustedKey,
      sharedAuthToken: sharedAuthToken,
    );

    return InitiatorClient._(client);
  }

  @override
  Stream<Event> get events => _client.events;

  @override
  void run() {
    _client.run();
  }
}

/// Client for an responder
class ResponderClient implements saltyrtc.ResponderClient {
  final saltyrtc.ResponderClient _client;

  ResponderClient._(this._client);

  factory ResponderClient.withAuthToken(
    Uri baseUri,
    saltyrtc.KeyStore ourPermanentKeys,
    List<saltyrtc.TaskBuilder> tasks, {
    required int pingInterval,
    required Uint8List expectedServerKey,
    required Uint8List initiatorTrustedKey,
    required Uint8List sharedAuthToken,
  }) {
    return ResponderClient._build(
      baseUri,
      ourPermanentKeys,
      tasks,
      pingInterval: pingInterval,
      expectedServerKey: expectedServerKey,
      initiatorTrustedKey: initiatorTrustedKey,
      sharedAuthToken: sharedAuthToken,
    );
  }

  factory ResponderClient.withTrustedKey(
    Uri baseUri,
    saltyrtc.KeyStore ourPermanentKeys,
    List<saltyrtc.TaskBuilder> tasks, {
    required int pingInterval,
    required Uint8List expectedServerKey,
    required Uint8List initiatorTrustedKey,
  }) {
    return ResponderClient._build(
      baseUri,
      ourPermanentKeys,
      tasks,
      pingInterval: pingInterval,
      expectedServerKey: expectedServerKey,
      initiatorTrustedKey: initiatorTrustedKey,
    );
  }

  factory ResponderClient._build(
    Uri baseUri,
    saltyrtc.KeyStore ourPermanentKeys,
    List<saltyrtc.TaskBuilder> tasks, {
    required int pingInterval,
    required Uint8List expectedServerKey,
    required Uint8List initiatorTrustedKey,
    Uint8List? sharedAuthToken,
  }) {
    final uri = _getUri(baseUri, ourPermanentKeys.publicKey);
    final client = saltyrtc.ResponderClient.build(
      crypto(),
      WebSocket(WebSocketChannel.connect(
        uri,
        protocols: saltyrtc.websocketProtocols,
      )),
      ourPermanentKeys,
      tasks,
      pingInterval: pingInterval,
      expectedServerKey: expectedServerKey,
      initiatorTrustedKey: initiatorTrustedKey,
      sharedAuthToken: sharedAuthToken,
    );

    return ResponderClient._(client);
  }

  @override
  Stream<Event> get events => _client.events;

  @override
  void run() {
    _client.run();
  }
}

/// Construct the uri where the last part of the path is the public of the initiator
Uri _getUri(Uri baseUri, Uint8List initiatorPublicKey) {
  return baseUri.replace(
      // we keep the original path because the server can be deployed behind a specific endpoint
      path: baseUri.path + '/${HEX.encode(initiatorPublicKey)}',
      query: null,
      fragment: null);
}
