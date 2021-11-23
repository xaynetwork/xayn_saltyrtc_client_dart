import 'dart:async' show StreamController;
import 'dart:typed_data' show Uint8List;

import 'package:test/test.dart';
import 'package:xayn_saltyrtc_client/events.dart' show Event;
import 'package:xayn_saltyrtc_client/src/crypto/crypto.dart'
    show InitialClientAuthMethod, KeyStore;
import 'package:xayn_saltyrtc_client/src/messages/id.dart' show Id;
import 'package:xayn_saltyrtc_client/src/messages/nonce/cookie.dart'
    show Cookie;
import 'package:xayn_saltyrtc_client/src/messages/s2c/client_auth.dart'
    show ClientAuth;
import 'package:xayn_saltyrtc_client/src/messages/s2c/client_hello.dart'
    show ClientHello;
import 'package:xayn_saltyrtc_client/src/messages/s2c/drop_responder.dart'
    show DropResponder;
import 'package:xayn_saltyrtc_client/src/protocol/phases/client_handshake_initiator.dart'
    show InitiatorClientHandshakePhase;
import 'package:xayn_saltyrtc_client/src/protocol/phases/client_handshake_responder.dart'
    show ResponderClientHandshakePhase;
import 'package:xayn_saltyrtc_client/src/protocol/phases/phase.dart'
    show Config, InitialCommon, InitiatorConfig, Phase, ResponderConfig;
import 'package:xayn_saltyrtc_client/src/protocol/phases/server_handshake.dart'
    show ResponderServerHandshakePhase, InitiatorServerHandshakePhase;
import 'package:xayn_saltyrtc_client/src/protocol/role.dart' show Role;
import 'package:xayn_saltyrtc_client/src/protocol/task.dart' show TaskBuilder;

import '../../crypto_mock.dart' show crypto;
import '../../network_mock.dart' show MockSyncWebSocket, PackageQueue;
import '../../server_mock.dart'
    show Decrypt, IntermediateState, MockServer, NonceAndMessage;
import '../../utils.dart' show setUpTesting;

void main() {
  setUpTesting();

  test('responder server handshake', () {
    final setupData =
        SetupData.init(Role.responder, makeResponderServerHandshakePhase);

    final server = setupData.server;
    final outMsgs = setupData.outMsgs;
    var phase = setupData.phase;

    final serverHelloResult = server.sendServerHelloToPhase(phase);
    phase = serverHelloResult.phase;

    // after server-hello we expect a client-hello
    final clientHello = checkClientHello(
        bytes: outMsgs.next(),
        clientPermanentPublicKey: setupData.clientPermanentKeys.publicKey);

    // set the client key as if the server received a client-hello message
    server.clientPermanentPublicKey = clientHello.message.key;

    // the responder must also send a client-auth
    checkClientAuth(
      bytes: outMsgs.next(),
      decrypt: server.decrypt,
      pingInterval: setupData.pingInterval,
      yourCookie: serverHelloResult.msgSentToClient.nonce.cookie,
      yourKey: server.permanentPublicKey,
    );

    final clientAddress = Id.responderId(5);
    final serverAuthResult = server.sendServerAuthResponderToPhase(
        phase, clientHello.nonce.cookie, false, clientAddress);
    expect(serverAuthResult.phase, isA<ResponderClientHandshakePhase>());

    phase = serverAuthResult.phase;
    expect(phase.common.address, equals(clientAddress));
  });

  test('initiator server handshake', () {
    final setupData =
        SetupData.init(Role.initiator, makeInitiatorServerHandshakePhase);

    final state = initiatorHandShakeTillClientAuth(setupData);

    final serverAuthResult = setupData.server.sendServerAuthInitiatorToPhase(
        state.phase, state.msgSentToClient.nonce.cookie, []);
    expect(serverAuthResult.phase, isA<InitiatorClientHandshakePhase>());

    final phase = serverAuthResult.phase;
    expect(phase.common.address, equals(Id.initiatorAddress));
  });

  test('initiator server handshake drop responders', () {
    final setupData =
        SetupData.init(Role.initiator, makeInitiatorServerHandshakePhase);

    final state = initiatorHandShakeTillClientAuth(setupData);

    // we generate 254 responder and we expect some of them to be dropped
    final responders = List.generate(254, (id) => Id.responderId(2 + id));

    setupData.server.sendServerAuthInitiatorToPhase(
      state.phase,
      state.msgSentToClient.nonce.cookie,
      responders,
    );

    // the threshold is 252 so we expect 2 drop message with id 2,3 (older are dropped first)
    for (final expectedId in responders.take(2).toList()) {
      final data = NonceAndMessage<DropResponder>.fromBytes(
        setupData.outMsgs.next(),
        setupData.server.decrypt,
      );
      expect(data.nonce.source, equals(Id.initiatorAddress));
      expect(data.nonce.destination, equals(Id.serverAddress));
      expect(data.message.id, equals(expectedId));
    }
  });
}

NonceAndMessage<ClientHello> checkClientHello({
  required Uint8List bytes,
  required Uint8List clientPermanentPublicKey,
}) {
  final data = NonceAndMessage<ClientHello>.fromBytes(bytes);
  final nonce = data.nonce;
  final msg = data.message;

  expect(msg.key, equals(clientPermanentPublicKey));

  expect(nonce.source, Id.unknownAddress);
  expect(nonce.destination, Id.serverAddress);
  expect(nonce.combinedSequence.isOverflowZero, isTrue);

  return data;
}

NonceAndMessage<ClientAuth> checkClientAuth({
  required Uint8List bytes,
  required Decrypt decrypt,
  required int pingInterval,
  required Cookie yourCookie,
  required Uint8List? yourKey,
}) {
  final data = NonceAndMessage<ClientAuth>.fromBytes(bytes, decrypt);
  final nonce = data.nonce;
  final msg = data.message;

  expect(msg.yourCookie, equals(yourCookie));
  expect(msg.yourKey, equals(yourKey));
  expect(msg.pingInterval, equals(pingInterval));
  expect(msg.subprotocols, contains('v1.saltyrtc.org'));

  expect(nonce.source, Id.unknownAddress);
  expect(nonce.destination, Id.serverAddress);

  return data;
}

IntermediateState<ClientAuth> initiatorHandShakeTillClientAuth(
    SetupData setupData) {
  final server = setupData.server;
  final outMsgs = setupData.outMsgs;
  var phase = setupData.phase;

  final serverHelloResult = server.sendServerHelloToPhase(phase);
  phase = serverHelloResult.phase;

  // set the client key as if the server server knows the path
  // the initiator is connected to
  server.clientPermanentPublicKey = setupData.clientPermanentKeys.publicKey;

  // the initiator must send a client-auth
  final clientAuth = checkClientAuth(
    bytes: outMsgs.next(),
    decrypt: server.decrypt,
    pingInterval: setupData.pingInterval,
    yourCookie: serverHelloResult.msgSentToClient.nonce.cookie,
    yourKey: server.permanentPublicKey,
  );

  return IntermediateState(clientAuth, phase);
}

class SetupData {
  final KeyStore clientPermanentKeys;
  final MockServer server;
  final PackageQueue outMsgs;
  final int pingInterval;
  final StreamController<Event> events;
  Phase phase;

  SetupData._(
    this.clientPermanentKeys,
    this.server,
    this.outMsgs,
    this.phase,
    this.pingInterval,
    this.events,
  );

  factory SetupData.init(
    Role role,
    Phase Function(InitialCommon, Config) initPhase, [
    int pingInterval = 13,
    List<TaskBuilder> tasks = const [],
  ]) {
    final clientPermanentKeys = crypto.createKeyStore();
    final server = MockServer();
    final ws = MockSyncWebSocket();
    final outMsgs = ws.sink.queue;
    final events = StreamController<Event>.broadcast();
    final common = InitialCommon(
      crypto,
      ws,
      events.sink,
    );
    final Config config;
    if (role == Role.initiator) {
      config = InitiatorConfig(
        permanentKeys: clientPermanentKeys,
        expectedServerPublicKey: server.permanentPublicKey,
        pingInterval: pingInterval,
        tasks: tasks,
        authMethod: InitialClientAuthMethod.fromEither(
            authToken: crypto.createAuthToken()),
      );
    } else {
      config = ResponderConfig(
        permanentKeys: clientPermanentKeys,
        expectedServerPublicKey: server.permanentPublicKey,
        pingInterval: pingInterval,
        tasks: tasks,
        initiatorPermanentPublicKey: crypto.createKeyStore().publicKey,
      );
    }

    final phase = initPhase(common, config);

    return SetupData._(
      clientPermanentKeys,
      server,
      outMsgs,
      phase,
      pingInterval,
      events,
    );
  }
}

InitiatorServerHandshakePhase makeInitiatorServerHandshakePhase(
  InitialCommon common,
  Config config,
) {
  return InitiatorServerHandshakePhase(
    common,
    config as InitiatorConfig,
  );
}

ResponderServerHandshakePhase makeResponderServerHandshakePhase(
  InitialCommon common,
  Config config,
) {
  return ResponderServerHandshakePhase(common, config as ResponderConfig);
}
