import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/src/crypto/crypto.dart'
    show AuthToken, CryptoBox, KeyStore;
import 'package:dart_saltyrtc_client/src/messages/close_code.dart'
    show CloseCode;
import 'package:dart_saltyrtc_client/src/messages/id.dart' show Id;
import 'package:dart_saltyrtc_client/src/messages/message.dart'
    show Message, TaskData;
import 'package:dart_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;
import 'package:dart_saltyrtc_client/src/messages/reader.dart'
    show MessageDecryptionExt, readMessage;
import 'package:dart_saltyrtc_client/src/protocol/error.dart'
    show ProtocolError, SaltyRtcError, ValidationError;
import 'package:dart_saltyrtc_client/src/protocol/events.dart' show Event;
import 'package:dart_saltyrtc_client/src/protocol/peer.dart'
    show CombinedSequencePair, CookiePair;
import 'package:dart_saltyrtc_client/src/protocol/phases/phase.dart' show Phase;
import 'package:dart_saltyrtc_client/src/protocol/task.dart'
    show Task, TaskBuilder;
import 'package:dart_saltyrtc_client/src/utils.dart' show Pair;
import 'package:test/expect.dart';

import 'crypto_mock.dart' show crypto, setUpCrypto;
import 'logging.dart' show setUpLogging;
import 'network_mock.dart' show EventQueue, MockSyncWebSocketSink, PackageQueue;

// Setups logging and crypto.
void setUpTesting() {
  setUpLogging();
  setUpCrypto();
}

Matcher throwsValidationError() {
  return throwsA(isA<ValidationError>());
}

Matcher throwsProtocolError({CloseCode closeCode = CloseCode.protocolError}) {
  bool errorHasExpectedState(Object? error) {
    if (error is! ProtocolError) {
      return true;
    } else {
      return error.closeCode == closeCode;
    }
  }

  return throwsA(allOf(isA<ProtocolError>(), predicate(errorHasExpectedState)));
}

Matcher throwsSaltyRtcError({CloseCode closeCode = CloseCode.protocolError}) {
  bool errorHasExpectedState(Object? error) {
    if (error is! SaltyRtcError) {
      return true;
    } else {
      return error.closeCode == closeCode;
    }
  }

  return throwsA(allOf(isA<SaltyRtcError>(), predicate(errorHasExpectedState)));
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
    final rawMessage = mapEncryptedMessage(_createRawMessage(message,
        encryptWith: encryptWith, mapNonce: mapNonce));
    return phaseAs(sendTo.handleMessage(rawMessage));
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

  void resetTestedClientKnowledge() {
    final old = testedPeer;
    testedPeer = MockKnowledgeAboutTestedPeer(address: old.address);
  }
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
        'Phase of type ${phase.runtimeType}, expected type $T');
  }
  return phase;
}

T noChange<T>(T v) => v;

class Io {
  PackageQueue sendPackages;
  EventQueue sendEvents;

  Io(this.sendPackages, this.sendEvents);

  T expectEventOfType<T extends Event>() {
    final event = sendEvents.next();
    expect(event, isA<T>());
    return event as T;
  }

  T expectMessageOfType<T extends Message>({required PeerData sendTo, CryptoBox? decryptWith}) {
    final package = sendPackages.next();
    final nonce = Nonce.fromBytes(package);
    expect(nonce.source, equals(sendTo.testedPeer.address));
    expect(nonce.destination, equals(sendTo.address));
    sendTo.testedPeer.cookiePair.updateAndCheck(nonce.cookie, nonce.source);
    sendTo.testedPeer.csPair.updateAndCheck(nonce.combinedSequence, nonce.source);
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

void runTest(Phase phase, List<Phase Function(Phase, Io)> steps) {
  final sink = phase.common.sink;
  final sendPackages = (sink as MockSyncWebSocketSink).queue;
  final sendEvents = phase.common.events as EventQueue;
  final io = Io(sendPackages, sendEvents);
  for (final step in steps) {
    phase = step(phase, io);
    expect(sendPackages, isEmpty);
    expect(phase.common.sink, same(sink));
    expect(sendEvents, isEmpty);
    expect(phase.common.events, same(sendEvents));
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
}
