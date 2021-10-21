import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/src/crypto/crypto.dart' show AuthToken;
import 'package:dart_saltyrtc_client/src/messages/close_code.dart'
    show CloseCode, CloseCodeToFromInt;
import 'package:dart_saltyrtc_client/src/messages/id.dart' show Id;
import 'package:dart_saltyrtc_client/src/messages/message.dart' show Message;
import 'package:dart_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;
import 'package:dart_saltyrtc_client/src/protocol/error.dart'
    show ProtocolErrorException;
import 'package:dart_saltyrtc_client/src/protocol/events.dart'
    show Event, HandoverToTask, InitiatorCouldNotDecrypt, InternalError;
import 'package:dart_saltyrtc_client/src/protocol/peer.dart' show Peer;
import 'package:dart_saltyrtc_client/src/protocol/phases/phase.dart'
    show Config, InitialCommon, Phase;
import 'package:dart_saltyrtc_client/src/protocol/role.dart' show Role;
import 'package:dart_saltyrtc_client/src/utils.dart' show EmitEventExt;
import 'package:test/test.dart';

import 'crypto_mock.dart' show crypto;
import 'network_mock.dart' show EventQueue, MockSyncWebSocket, PackageQueue;
import 'utils.dart' show Io, setUpTesting;

void main() {
  setUpTesting();

  group('.close', () {
    test('calls phase.doClose and uses the returned close code', () {
      final closeCode = CloseCode.invalidKey;
      final closeCode2 = CloseCode.goingAway.toInt();

      final tests = <Function()>[];
      final phase = TestPhase(doCloseFn: (closeCode, phase) {
        tests.add(() {
          expect(closeCode, equals(closeCode));
        });
        return closeCode2;
      });
      phase.close(closeCode, 'foo');
      tests.removeLast()();
      expect(tests, isEmpty);
      expect(phase.webSocket.isClosed, isTrue);
      expect(phase.webSocket.closeCode, equals(closeCode2));
      expect(phase.io.sendEvents, isEmpty);
    });
    test(
        'if phase.doClose throws a InternalError even is emitted and internalError is used as close code',
        () {
      final phase = TestPhase(doCloseFn: (closeCode, phase) {
        throw StateError('foo bar');
      });
      phase.close(CloseCode.closingNormal, 'lala');
      final event = phase.io.expectEventOfType<InternalError>();
      expect(event.error, isA<StateError>());
      expect(
          phase.webSocket.closeCode, equals(CloseCode.internalError.toInt()));
    });

    test('calling close multiple times won\'t call doClose multiple times', () {
      var callCount = 0;
      final phase = TestPhase(doCloseFn: (closeCode, phase) {
        callCount += 1;
        return closeCode?.toInt();
      });
      phase.close(CloseCode.goingAway, 'a');
      phase.close(CloseCode.internalError, 'b');
      phase.close(CloseCode.invalidKey, 'c');
      expect(callCount, equals(1));
    });

    test('sets isClosing before calling doClose', () {
      bool? isClosed;
      final phase = TestPhase(doCloseFn: (closeCode, phase) {
        isClosed = phase.isClosingWsStream;
      });
      phase.close(CloseCode.closingNormal, 'lala');
      expect(isClosed, isTrue);
      expect(phase.isClosingWsStream, isTrue);
    });
  });

  group('notifyConnectionClosed', () {
    test('sets isClosed immediately but does not call doClose', () {
      bool called = false;
      final phase = TestPhase(doCloseFn: (closeCode, phase) {
        called = true;
      });
      phase.common.webSocket.sink.close(CloseCode.closingNormal.toInt());
      phase.notifyWsStreamClosed();
      expect(called, isFalse);
      expect(phase.isClosingWsStream, isTrue);
    });

    test('if not manually closed close the events and maybe emits an Event',
        () {
      var phase = TestPhase();
      phase.common.webSocket.sink
          .close(CloseCode.initiatorCouldNotDecrypt.toInt());
      phase.notifyWsStreamClosed();
      phase.io.expectEventOfType<InitiatorCouldNotDecrypt>();
      expect(phase.isClosingWsStream, isTrue);
      expect(phase.io.sendEvents.isClosed, isTrue);

      phase = TestPhase();
      phase.common.webSocket.sink.close(CloseCode.closingNormal.toInt());
      phase.notifyWsStreamClosed();
      expect(phase.io.sendEvents, isEmpty);
      expect(phase.isClosingWsStream, isTrue);
      expect(phase.io.sendEvents.isClosed, isTrue);
    });

    test('if manually closed do not emit event but still close events', () {
      final phase = TestPhase();
      phase.close(CloseCode.initiatorCouldNotDecrypt, 'foo');
      expect(phase.isClosingWsStream, isTrue);
      expect(phase.io.sendEvents.isClosed, isFalse);
      phase.notifyWsStreamClosed();
      expect(phase.isClosingWsStream, isTrue);
      expect(phase.io.sendEvents.isClosed, isTrue);
    });

    test('runs only once', () {
      final phase = TestPhase();
      phase.close(CloseCode.goingAway, 'foo');
      phase.notifyWsStreamClosed();
      expect(() {
        phase.notifyWsStreamClosed();
      }, throwsA(isA<StateError>()));
    });
  });

  test('handover closes the WS but not events', () {
    Function()? doCloseTest;
    final phase = TestPhase(doCloseFn: (closeCode, phase) {
      doCloseTest = () {
        expect(closeCode, equals(CloseCode.handover));
      };
      return CloseCode.goingAway.toInt();
    });
    phase.close(CloseCode.handover, 'handover', receivedCloseMsg: true);
    phase.notifyWsStreamClosed();
    expect(phase.webSocket.isClosed, isTrue);
    expect(phase.webSocket.closeCode, equals(CloseCode.goingAway.toInt()));
    doCloseTest!();
    phase.io.expectEventOfType<HandoverToTask>();
    expect(phase.io.sendEvents.isClosed, isFalse);
    expect(phase.io.sendEvents.isClosed, isFalse);
  });
}

class TestPhase extends Phase {
  int cancelTaskCallCount = 0;
  int closeMsgCallCount = 0;
  bool closeMsgWillBeSend = false;
  int handoverCallCount = 0;
  final MockSyncWebSocket webSocket;
  final Io io;
  @override
  final InitialCommon common;

  factory TestPhase() {
    final webSocket = MockSyncWebSocket();
    final io = Io(PackageQueue(), EventQueue());
    final common = InitialCommon(crypto, webSocket, io.sendEvents);

    return TestPhase._(webSocket, io, common);
  }

  TestPhase._(this.webSocket, this.io, this.common);

  @override
  Uint8List buildPacket(Message msg, Peer receiver,
          {bool encrypt = true, AuthToken? authToken}) =>
      throw UnimplementedError();

  @override
  Config get config => throw UnimplementedError();

  @override
  void emitEvent(Event event, [StackTrace? st]) =>
      common.events.emitEvent(event, st);

  @override
  Peer? getPeerWithId(Id id) => throw UnimplementedError();

  @override
  Phase handleMessage(Uint8List bytes) => throw UnimplementedError();

  @override
  Phase onProtocolError(ProtocolErrorException e, Id? source) =>
      throw UnimplementedError();

  @override
  Role get role => throw UnimplementedError();

  @override
  Phase run(Peer source, Uint8List msgBytes, Nonce nonce) =>
      throw UnimplementedError();

  @override
  void send(Uint8List bytes) => throw UnimplementedError();

  @override
  void sendMessage(Message msg,
          {required Peer to, bool encrypt = true, AuthToken? authToken}) =>
      throw UnimplementedError();

  @override
  void validateNonceDestination(Nonce nonce) => throw UnimplementedError();

  @override
  void cancelTask({bool serverDisconnected = false}) {
    cancelTaskCallCount += 1;
  }

  @override
  bool sendCloseMsgToClientIfNecessary(CloseCode closeCode) {
    closeMsgCallCount += 1;
    return closeMsgWillBeSend;
  }

  @override
  void tellTaskThatHandoverCompleted() {
    handoverCallCount += 1;
  }
}
