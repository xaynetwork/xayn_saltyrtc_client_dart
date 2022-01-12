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

import 'dart:typed_data' show Uint8List;

import 'package:test/expect.dart';
import 'package:xayn_saltyrtc_client/events.dart' show Event;
import 'package:xayn_saltyrtc_client/src/crypto/crypto.dart'
    show AuthToken, CryptoBox, KeyStore;
import 'package:xayn_saltyrtc_client/src/messages/c2c/task_message.dart'
    show TaskMessage;
import 'package:xayn_saltyrtc_client/src/messages/close_code.dart'
    show CloseCode;
import 'package:xayn_saltyrtc_client/src/messages/id.dart' show Id, ClientId;
import 'package:xayn_saltyrtc_client/src/messages/message.dart'
    show Message, TaskData;
import 'package:xayn_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;
import 'package:xayn_saltyrtc_client/src/messages/reader.dart'
    show MessageDecryptionExt, readMessage;
import 'package:xayn_saltyrtc_client/src/protocol/error.dart'
    show ProtocolErrorException, ValidationException;
import 'package:xayn_saltyrtc_client/src/protocol/peer.dart'
    show CombinedSequencePair, CookiePair;
import 'package:xayn_saltyrtc_client/src/protocol/phases/phase.dart'
    show AfterServerHandshakeCommon, InitialCommon, Phase;
import 'package:xayn_saltyrtc_client/src/protocol/task.dart'
    show Task, TaskBuilder, CancelReason;
import 'package:xayn_saltyrtc_client/src/utils.dart' show Pair;

import 'crypto_mock.dart' show crypto, setUpCrypto;
import 'logging.dart' show setUpLogging;
import 'network_mock.dart'
    show EventQueue, MockSyncWebSocket, MockSyncWebSocketSink, PackageQueue;

// Setups logging and crypto.
void setUpTesting() {
  setUpLogging();
  setUpCrypto();
}

Matcher throwsValidationError() {
  return throwsA(isA<ValidationException>());
}

Matcher throwsProtocolError({CloseCode closeCode = CloseCode.protocolError}) {
  bool errorHasExpectedState(Object? error) {
    if (error is! ProtocolErrorException) {
      return true;
    } else {
      return error.closeCode == closeCode;
    }
  }

  return throwsA(
    allOf(isA<ProtocolErrorException>(), predicate(errorHasExpectedState)),
  );
}

class MockKnowledgeAboutTestedPeer {
  KeyStore? permanentKey;
  KeyStore? theirSessionKey;
  KeyStore? ourSessionKey;
  final Id address;
  final CombinedSequencePair csPair;
  final CookiePair cookiePair;

  MockKnowledgeAboutTestedPeer({
    required this.address,
    this.permanentKey,
    this.theirSessionKey,
    this.ourSessionKey,
  })  : csPair = CombinedSequencePair.fromRandom(crypto),
        cookiePair = CookiePair.fromRandom(crypto);
}

class PeerData {
  final AuthToken? authToken;
  final Id address;
  final KeyStore permanentKey;
  MockKnowledgeAboutTestedPeer testedPeer;

  PeerData({
    required this.address,
    required Id testedPeerId,
    this.authToken,
  })  : permanentKey = crypto.createKeyStore(),
        testedPeer = MockKnowledgeAboutTestedPeer(address: testedPeerId);

  N sendAndTransitToPhase<N extends Phase>({
    required Message message,
    required Phase sendTo,
    required CryptoBox? encryptWith,
    // use to e.g. create "bad" nonces
    Nonce Function(Nonce) mapNonce = noChange,
    // use to e.g. create "bad" encrypted messages"
    Uint8List Function(Uint8List) mapEncryptedMessage = noChange,
  }) {
    expect(sendTo.common.address, equals(testedPeer.address));
    final rawMessage = mapEncryptedMessage(
      _createRawMessage(
        message,
        encryptWith: encryptWith,
        mapNonce: mapNonce,
      ),
    );

    final nextPhase = sendTo.handleMessage(rawMessage);
    expect(nextPhase.isClosingWsStream, isFalse);
    return phaseAs<N>(nextPhase);
  }

  int sendAndClose({
    required Message message,
    required Phase sendTo,
    required CryptoBox? encryptWith,
    // use to e.g. create "bad" nonces
    Nonce Function(Nonce) mapNonce = noChange,
    // use to e.g. create "bad" encrypted messages"
    Uint8List Function(Uint8List) mapEncryptedMessage = noChange,
  }) {
    expect(sendTo.common.address, equals(testedPeer.address));
    final rawMessage = mapEncryptedMessage(
      _createRawMessage(
        message,
        encryptWith: encryptWith,
        mapNonce: mapNonce,
      ),
    );

    final nextPhase = sendTo.handleMessage(rawMessage);
    expect(nextPhase.isClosingWsStream, isTrue);
    final sink = nextPhase.common.webSocket.sink as MockSyncWebSocketSink;
    expect(sink.isClosed, isTrue);
    expect(sink.closeCode, isNotNull);
    return sink.closeCode!;
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
      Nonce(testedPeer.cookiePair.ours, address, testedPeer.address, csn),
    );
    return message.buildPackage(nonce, encryptWith: encryptWith);
  }

  void resetTestedClientKnowledge() {
    final old = testedPeer;
    testedPeer = MockKnowledgeAboutTestedPeer(address: old.address);
  }
}

Pair<PeerData, AfterServerHandshakeCommon> createAfterServerHandshakeState(
  ClientId clientAddress,
) {
  final server = PeerData(
    address: Id.serverAddress,
    testedPeerId: clientAddress,
  );
  server.testedPeer.ourSessionKey = crypto.createKeyStore();
  server.testedPeer.permanentKey = crypto.createKeyStore();

  final ws = MockSyncWebSocket();
  final events = EventQueue();
  final common = InitialCommon(crypto, ws, events);
  common.server.setPermanentSharedKey(
    crypto.createSharedKeyStore(
      ownKeyStore: server.testedPeer.permanentKey!,
      remotePublicKey: server.permanentKey.publicKey,
    ),
  );
  common.server.setSessionSharedKey(
    crypto.createSharedKeyStore(
      ownKeyStore: server.testedPeer.permanentKey!,
      remotePublicKey: server.testedPeer.ourSessionKey!.publicKey,
    ),
  );
  common.server.cookiePair
      .updateAndCheck(server.testedPeer.cookiePair.ours, Id.serverAddress);
  common.server.csPair
      .updateAndCheck(server.testedPeer.csPair.ours, Id.serverAddress);

  common.address = clientAddress;

  return Pair(server, AfterServerHandshakeCommon(common));
}

T messageAs<T extends Message>(Message? msg) {
  if (msg == null) {
    throw AssertionError('Message expected but none was send.');
  }
  if (msg is! T) {
    throw AssertionError('Message of type ${msg.type}, expected type $T');
  }
  return msg;
}

T phaseAs<T extends Phase>(Phase phase) {
  if (phase is! T) {
    throw AssertionError(
      'Phase of type ${phase.runtimeType}, expected type $T',
    );
  }
  return phase;
}

T noChange<T>(T v) => v;

class Io {
  PackageQueue sendPackages;
  EventQueue sendEvents;

  Io(this.sendPackages, this.sendEvents);

  T expectEventOfType<T extends Event>({bool? isClosingError}) {
    final Event event = sendEvents.next(isError: isClosingError);
    expect(event, isA<T>());
    return event as T;
  }

  T expectMessageOfType<T extends Message>({
    required PeerData sendTo,
    CryptoBox? decryptWith,
  }) {
    final package = sendPackages.next();
    final nonce = Nonce.fromBytes(package);
    expect(nonce.source, equals(sendTo.testedPeer.address));
    expect(nonce.destination, equals(sendTo.address));
    sendTo.testedPeer.cookiePair.updateAndCheck(nonce.cookie, nonce.source);
    sendTo.testedPeer.csPair
        .updateAndCheck(nonce.combinedSequence, nonce.source);
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

typedef TestStep = Phase? Function(Phase, Io);

void runTest(Phase initialPhase, List<TestStep> steps) {
  Phase? phase = initialPhase;
  final sink = phase.common.webSocket.sink;
  final sendPackages = (sink as MockSyncWebSocketSink).queue;
  final sendEvents = phase.common.events as EventQueue;
  final io = Io(sendPackages, sendEvents);
  for (final step in steps) {
    if (phase == null) {
      throw AssertionError('closed before all test did run');
    }
    expect(phase.common.webSocket.sink, same(sink));
    expect(phase.common.events, same(sendEvents));
    phase = step(phase, io);
    expect(sendPackages, isEmpty);
    expect(sendEvents, isEmpty);
  }
}

class TestTaskBuilder extends TaskBuilder {
  @override
  final String name;

  final TaskData? initialResponderData;

  TestTask? lastInitiatorTask;
  TestTask? lastResponderTask;

  TestTaskBuilder(this.name, {this.initialResponderData});

  @override
  Pair<Task, TaskData?> buildInitiatorTask(TaskData? initialResponderData) {
    TaskData? data;
    if (initialResponderData == null) {
      data = {
        'initWasCalled': [2, 0, 12]
      };
    } else {
      data = Map.of(initialResponderData);
      data['initWasCalled'] = [1, 0, 12];
    }
    final task = TestTask(name, initData: data);
    lastInitiatorTask = task;
    return Pair(task, data);
  }

  @override
  Task buildResponderTask(TaskData? initiatorData) {
    final task = TestTask(name, initData: initiatorData);
    lastResponderTask = task;
    return task;
  }

  @override
  TaskData? getInitialResponderData() => initialResponderData;
}

class TestTask extends Task {
  final String name;

  final TaskData? initData;

  @override
  final List<String> supportedTypes;

  TestTask(this.name, {this.initData, this.supportedTypes = const ['magic']});

  @override
  void handleCancel(CancelReason reason) {
    throw UnimplementedError();
  }

  @override
  void handleEvent(Event event) {
    throw UnimplementedError();
  }

  @override
  void handleMessage(TaskMessage msg) {
    throw UnimplementedError();
  }

  @override
  void start() {}
}
