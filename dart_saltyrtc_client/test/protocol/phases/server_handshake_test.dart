import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/src/messages/id.dart' show Id;
import 'package:dart_saltyrtc_client/src/messages/message.dart';
import 'package:dart_saltyrtc_client/src/messages/nonce/cookie.dart'
    show Cookie;
import 'package:dart_saltyrtc_client/src/messages/s2c/client_auth.dart'
    show ClientAuth;
import 'package:dart_saltyrtc_client/src/messages/s2c/client_hello.dart'
    show ClientHello;
import 'package:dart_saltyrtc_client/src/messages/s2c/drop_responder.dart';
import 'package:dart_saltyrtc_client/src/protocol/phases/client_handshake_initiator.dart'
    show InitiatorClientHandshakePhase;
import 'package:dart_saltyrtc_client/src/protocol/phases/client_handshake_responder.dart'
    show ResponderClientHandshakePhase;
import 'package:dart_saltyrtc_client/src/protocol/phases/phase.dart';
import 'package:test/test.dart';

import '../../logging.dart' show setUpLogging;
import '../../server_mock.dart' show NonceAndMessage, Decrypt;
import '../../utils.dart'
    show
        SetupData,
        makeInitiatorServerHandshakePhase,
        makeResponderServerHandshakePhase;

void main() {
  setUpLogging();

  test('responder server handshake', () async {
    final setupData = SetupData.init(makeResponderServerHandshakePhase);

    final server = setupData.server;
    final outMsgs = setupData.outMsgs;
    var phase = setupData.phase;

    final serverHelloResult = server.sendServerHello(phase);
    phase = serverHelloResult.nextPhase;

    // after server-hello we expect a client-hello
    final clientHello = checkClientHello(
        bytes: await outMsgs.next,
        clientPermanentPublicKey: setupData.clientPermanentKeys.publicKey);

    // set the client key as if the server received a client-hello message
    server.clientPermanentPublicKey = clientHello.message.key;

    // the responder must also send a client-auth
    checkClientAuth(
      bytes: await outMsgs.next,
      decrypt: server.decrypt,
      pingInterval: setupData.pingInterval,
      yourCookie: serverHelloResult.msgSentToClient.nonce.cookie,
      yourKey: server.permanentPublicKey,
    );

    final clientAddress = Id.responderId(5);
    final serverAuthResult = server.sendServerAuthResponder(
        phase, clientHello.nonce.cookie, false, clientAddress);
    expect(serverAuthResult.nextPhase, isA<ResponderClientHandshakePhase>());

    phase = serverAuthResult.nextPhase;
    expect(phase.common.address, equals(clientAddress));
  });

  test('initiator server handshake', () async {
    final setupData = SetupData.init(makeInitiatorServerHandshakePhase);

    final state = await initiatorHandShakeTillClientAuth(setupData);

    final serverAuthResult = setupData.server.sendServerAuthInitiator(
        state.phase, state.lastSentMessage.nonce.cookie, []);
    expect(serverAuthResult.nextPhase, isA<InitiatorClientHandshakePhase>());

    final phase = serverAuthResult.nextPhase;
    expect(phase.common.address, equals(Id.initiatorAddress));
  });

  test('initiator server handshake drop responders', () async {
    final setupData = SetupData.init(makeInitiatorServerHandshakePhase);

    final state = await initiatorHandShakeTillClientAuth(setupData);

    // we generate 254 responder and we expect some of them to be dropped
    final responders = List.generate(254, (id) => Id.responderId(2 + id));

    final serverAuthResult = setupData.server.sendServerAuthInitiator(
      state.phase,
      state.lastSentMessage.nonce.cookie,
      responders,
    );

    // the threshold is 252 so we expect 2 drop message with id 2,3 (older are dropped first)
    for (final expectedId in responders.take(2).toList()) {
      final data = NonceAndMessage<DropResponder>.fromBytes(
        await setupData.outMsgs.next,
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
  required Uint8List yourKey,
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

class IntermediateState<M extends Message> {
  final Phase phase;
  final NonceAndMessage<M> lastSentMessage;

  IntermediateState(this.phase, this.lastSentMessage);
}

Future<IntermediateState<ClientAuth>> initiatorHandShakeTillClientAuth(
    SetupData setupData) async {
  final server = setupData.server;
  final outMsgs = setupData.outMsgs;
  var phase = setupData.phase;

  final serverHelloResult = server.sendServerHello(phase);
  phase = serverHelloResult.nextPhase;

  // set the client key as if the server server knows the path
  // the initiator is connected to
  server.clientPermanentPublicKey = setupData.clientPermanentKeys.publicKey;

  // the initiator must send a client-auth
  final clientAuth = checkClientAuth(
    bytes: await outMsgs.next,
    decrypt: server.decrypt,
    pingInterval: setupData.pingInterval,
    yourCookie: serverHelloResult.msgSentToClient.nonce.cookie,
    yourKey: server.permanentPublicKey,
  );

  return IntermediateState(phase, clientAuth);
}
