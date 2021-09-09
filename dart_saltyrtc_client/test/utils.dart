import 'dart:typed_data' show Uint8List;

import 'package:async/async.dart' show StreamQueue;
import 'package:dart_saltyrtc_client/src/crypto/crypto.dart'
    show Crypto, KeyStore;
import 'package:dart_saltyrtc_client/src/protocol/peer.dart' show Initiator;
import 'package:dart_saltyrtc_client/src/protocol/phases/phase.dart'
    show Phase, Common, InitiatorData, ResponderData;
import 'package:dart_saltyrtc_client/src/protocol/phases/server_handshake.dart'
    show InitiatorServerHandshakePhase, ResponderServerHandshakePhase;
import 'package:dart_saltyrtc_client/src/protocol/task.dart' show Task;

import 'crypto_mock.dart' show MockCrypto;
import 'network_mock.dart' show MockWebSocket;
import 'server_mock.dart' show MockServer;

class SetupData {
  final Crypto crypto;
  final KeyStore clientPermanentKeys;
  final MockServer server;
  final StreamQueue<Uint8List> outMsgs;
  final int pingInterval;
  Phase phase;

  SetupData._(
    this.crypto,
    this.clientPermanentKeys,
    this.server,
    this.outMsgs,
    this.phase,
    this.pingInterval,
  );

  factory SetupData.init(
    Phase Function(Common, int) initPhase, [
    int pingInterval = 13,
    List<Task> tasks = const [],
  ]) {
    final crypto = MockCrypto();
    final clientPermanentKeys = crypto.createKeyStore();
    final server = MockServer(crypto);
    final ws = MockWebSocket();
    final outMsgs = StreamQueue<Uint8List>(ws.stream);
    final common = Common(
      MockCrypto(),
      clientPermanentKeys,
      server.permanentPublicKey,
      tasks,
      ws,
    );
    final phase = initPhase(common, pingInterval);

    return SetupData._(
        crypto, clientPermanentKeys, server, outMsgs, phase, pingInterval);
  }
}

InitiatorServerHandshakePhase makeInitiatorServerHandshakePhase(
  Common common,
  int pingInterval, [
  InitiatorData? data,
]) {
  return InitiatorServerHandshakePhase(
    common,
    pingInterval,
    data ?? InitiatorData(null),
  );
}

ResponderServerHandshakePhase makeResponderServerHandshakePhase(
  Common common,
  int pingInterval, [
  ResponderData? data,
]) {
  return ResponderServerHandshakePhase(
    common,
    pingInterval,
    data ?? ResponderData(Initiator(common.crypto)),
  );
}
