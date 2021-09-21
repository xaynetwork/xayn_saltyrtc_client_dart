import 'dart:typed_data' show Uint8List;

import 'package:async/async.dart' show StreamQueue;
import 'package:dart_saltyrtc_client/src/crypto/crypto.dart'
    show AuthToken, Crypto, CryptoBox, InitialClientAuthMethod, KeyStore;
import 'package:dart_saltyrtc_client/src/messages/id.dart' show Id;
import 'package:dart_saltyrtc_client/src/messages/message.dart'
    show Message, TaskData;
import 'package:dart_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;
import 'package:dart_saltyrtc_client/src/messages/reader.dart'
    show MessageDecryptionExt, readMessage;
import 'package:dart_saltyrtc_client/src/protocol/error.dart'
    show ProtocolError, ValidationError;
import 'package:dart_saltyrtc_client/src/protocol/peer.dart'
    show CombinedSequencePair, CookiePair, Initiator;
import 'package:dart_saltyrtc_client/src/protocol/phases/phase.dart'
    show Phase, Common, ResponderData, ClientHandshakeInput;
import 'package:dart_saltyrtc_client/src/protocol/phases/server_handshake.dart'
    show InitiatorServerHandshakePhase, ResponderServerHandshakePhase;
import 'package:dart_saltyrtc_client/src/protocol/task.dart' show Task;
import 'package:test/expect.dart';

import 'crypto_mock.dart' show MockCrypto;
import 'network_mock.dart' show MockWebSocket, MockWebSocket2, PackageQueue;
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
    Phase Function(Common, ClientHandshakeInput, int) initPhase, [
    int pingInterval = 13,
    List<Task> tasks = const [],
  ]) {
    final crypto = MockCrypto();
    final clientPermanentKeys = crypto.createKeyStore();
    final server = MockServer(crypto);
    final ws = MockWebSocket();
    final outMsgs = StreamQueue<Uint8List>(ws.stream);
    final common = Common(
      crypto,
      clientPermanentKeys,
      server.permanentPublicKey,
      ws,
    );
    final clientHandshakeInput = ClientHandshakeInput(
        tasks: tasks,
        authMethod: InitialClientAuthMethod.fromEither(
            authToken: crypto.createAuthToken()));
    final phase = initPhase(common, clientHandshakeInput, pingInterval);

    return SetupData._(
        crypto, clientPermanentKeys, server, outMsgs, phase, pingInterval);
  }
}

InitiatorServerHandshakePhase makeInitiatorServerHandshakePhase(
  Common common,
  ClientHandshakeInput clientHandshakeInput,
  int pingInterval,
) {
  return InitiatorServerHandshakePhase(
    common,
    clientHandshakeInput,
    pingInterval,
  );
}

ResponderServerHandshakePhase makeResponderServerHandshakePhase(
  Common common,
  ClientHandshakeInput clientHandshakeInput,
  int pingInterval, [
  ResponderData? data,
]) {
  return ResponderServerHandshakePhase(
    common,
    clientHandshakeInput,
    pingInterval,
    data ?? ResponderData(Initiator(common.crypto)),
  );
}

Matcher throwsValidationError({bool isProtocolError = true}) {
  final ifValidationErrorHasExpectedState = (Object? error) {
    if (error is! ValidationError) {
      return true;
    } else {
      return error.isProtocolError == isProtocolError;
    }
  };
  return throwsA(allOf(
      isA<ValidationError>(), predicate(ifValidationErrorHasExpectedState)));
}

Matcher throwsProtocolError() {
  return throwsA(isA<ProtocolError>());
}

class MockKnowledgeAboutTestedPeer {
  KeyStore? permanentKey;
  KeyStore? theirSessionKey;
  KeyStore? ourSessionKey;
  final Id address;
  final CombinedSequencePair csPair;
  final CookiePair cookiePair;

  MockKnowledgeAboutTestedPeer({
    required Crypto crypto,
    required this.address,
    this.permanentKey,
    this.theirSessionKey,
    this.ourSessionKey,
  })  : csPair = CombinedSequencePair.fromRandom(crypto),
        cookiePair = CookiePair.fromRandom(crypto);
}

class PeerData {
  final Crypto crypto;
  final AuthToken? authToken;
  final Id address;
  final KeyStore permanentKey;
  final MockKnowledgeAboutTestedPeer testedPeer;

  PeerData({
    required this.crypto,
    required this.address,
    required Id testedPeerId,
    this.authToken,
  })  : permanentKey = crypto.createKeyStore(),
        testedPeer =
            MockKnowledgeAboutTestedPeer(crypto: crypto, address: testedPeerId);

  N sendAndTransitToPhase<N extends Phase>({
    required Message message,
    required Phase to,
    required CryptoBox? encryptWith,
    // use to e.g. create "bad" nonces
    Nonce Function(Nonce) mapNonce = noChange,
    // use to e.g. create "bad" encrypted messages"
    Uint8List Function(Uint8List) mapEncryptedMessage = noChange,
  }) {
    expect(to.common.address, equals(testedPeer.address));
    final rawMessage = mapEncryptedMessage(_createRawMessage(message,
        encryptWith: encryptWith, mapNonce: mapNonce));
    return phaseAs(to.handleMessage(rawMessage));
  }

  Uint8List _createRawMessage(
    Message message, {
    required CryptoBox? encryptWith,
    // use to e.g. create "bad" nonces
    Nonce Function(Nonce) mapNonce = noChange,
  }) {
    final csn = testedPeer.csPair.ours;
    csn.next();
    final nonce = mapNonce(
        Nonce(testedPeer.cookiePair.ours, address, testedPeer.address, csn));
    return message.buildPackage(nonce, encryptWith: encryptWith);
  }

  T expectMessageOfType<T extends Message>(PackageQueue packages,
      {required CryptoBox? decryptWith}) {
    final package = packages.takeNextPackage();
    final nonce = Nonce.fromBytes(package);
    expect(nonce.source, equals(testedPeer.address));
    expect(nonce.destination, equals(address));
    testedPeer.cookiePair.updateAndCheck(nonce.cookie, nonce.source);
    testedPeer.csPair.updateAndCheck(nonce.combinedSequence, nonce.source);
    final payload = Uint8List.sublistView(package, Nonce.totalLength);
    final Message msg;
    if (decryptWith == null) {
      msg = readMessage(payload);
    } else {
      msg = decryptWith.readEncryptedMessageOfType<T>(
        msgBytes: payload,
        nonce: nonce,
        msgType: T.runtimeType.toString(),
      );
    }
    expect(msg, isA<T>());
    return msg as T;
  }
}

T messageAs<T extends Message>(Message? msg) {
  if (msg == null) {
    throw AssertionError('Message expected but non was send.');
  }
  if (msg is! T) {
    throw AssertionError(
        'Message of type ${msg.type}, not of expected type $T');
  }
  return msg;
}

T phaseAs<T extends Phase>(Phase phase) {
  if (phase is! T) {
    throw AssertionError(
        'Phase of type ${phase.runtimeType}, not of expected type $T');
  }
  return phase;
}

T noChange<T>(T v) => v;

void runTest(Phase phase, List<Phase Function(Phase, PackageQueue)> steps) {
  final sink = phase.common.sink;
  var packageQueue = (sink as MockWebSocket2).queue;
  for (final step in steps) {
    phase = step(phase, packageQueue);
    expect(packageQueue, isEmpty);
    expect(phase.common.sink, same(sink));
  }
}

class TestTask extends Task {
  @override
  final String name;

  bool initWasCalled = false;

  TestTask(this.name);

  @override
  TaskData? get data => {
        'soda': [12, 3, 2]
      };

  @override
  void initialize(TaskData? data) {
    expect(data, equals(this.data));
    initWasCalled = true;
  }

  @override
  List<String> get supportedTypes => ['magic'];
}
