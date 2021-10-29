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
    show
        Event,
        HandoverToTask,
        InitiatorCouldNotDecrypt,
        UnexpectedStatus,
        UnexpectedStatusVariant;
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
    test('close ws and emit event if triggered by close msg', () {
      final phase = TestPhase();
      phase.close(CloseCode.initiatorCouldNotDecrypt, 'foo',
          receivedCloseMsg: true);
      phase.io.expectEventOfType<InitiatorCouldNotDecrypt>();
      expect(phase.webSocket.closeCode, equals(CloseCode.goingAway.toInt()));
    });

    test('cancelTask exactly if not close code == handover', () {
      var phase = TestPhase();
      phase.close(CloseCode.goingAway, 'foo');
      expect(phase.cancelTaskCallCount, equals(1));

      phase = TestPhase();
      phase.close(CloseCode.handover, 'foo');
      expect(phase.cancelTaskCallCount, equals(0));
    });

    test('cancelTask on close even if handover proceeded', () {
      var phase = TestPhase();
      phase.close(CloseCode.handover, 'foo');
      expect(phase.cancelTaskCallCount, equals(0));
      phase.close(CloseCode.protocolError, 'bar');
      expect(phase.cancelTaskCallCount, equals(1));

      phase = TestPhase();
      phase.close(CloseCode.handover, 'fly');
      phase.notifyWsStreamClosed();
      phase.io.expectEventOfType<HandoverToTask>();
      phase.close(CloseCode.goingAway, 'dor');
      expect(phase.cancelTaskCallCount, equals(1));
      expect(phase.io.sendEvents.isClosed, isFalse);
    });

    test('send close msg if necessary', () {
      final phase = TestPhase();
      phase.closeMsgWillBeSend = true;
      phase.close(CloseCode.protocolError, 'foo');
      expect(phase.lastSendCloseCode, equals(CloseCode.protocolError));
      expect(phase.webSocket.closeCode, equals(CloseCode.goingAway.toInt()));
    });

    test('if no close msg is send close WS with close code', () {
      final phase = TestPhase();
      phase.closeMsgWillBeSend = false;
      phase.close(CloseCode.protocolError, 'foo');
      expect(phase.lastSendCloseCode, isNull);
      expect(
          phase.webSocket.closeCode, equals(CloseCode.protocolError.toInt()));
    });

    test('calling close multiple times has no effect (besides cancelTask)', () {
      final phase = TestPhase();
      phase.close(CloseCode.protocolError, 'foo', receivedCloseMsg: true);
      expect(phase.cancelTaskCallCount, equals(1));
      phase.close(CloseCode.handover, 'foo', receivedCloseMsg: true);
      expect(phase.cancelTaskCallCount, equals(1));
      phase.close(CloseCode.initiatorCouldNotDecrypt, 'foo',
          receivedCloseMsg: true);
      expect(phase.cancelTaskCallCount, equals(2));
      phase.close(CloseCode.protocolError, 'foo', receivedCloseMsg: true);
      expect(phase.cancelTaskCallCount, equals(3));

      final event = phase.io.expectEventOfType<UnexpectedStatus>();
      expect(
          event,
          equals(UnexpectedStatus.unchecked(
              UnexpectedStatusVariant.protocolError, 3001)));
      expect(phase.io.sendEvents, isEmpty);
    });
  });

  group('.notifyWsStreamClosed', () {
    test('in case of a started handover complete it', () {
      final phase = TestPhase();
      phase.close(CloseCode.handover, 'foo');
      expect(phase.io.sendEvents, isEmpty);
      expect(phase.webSocket.closeCode, equals(CloseCode.handover.toInt()));
      expect(phase.io.sendEvents.isClosed, isFalse);
      phase.notifyWsStreamClosed();
      expect(phase.io.sendEvents.isClosed, isFalse);
      expect(phase.handoverCallCount, equals(1));
      phase.io.expectEventOfType<HandoverToTask>();
      expect(phase.cancelTaskCallCount, equals(0));
    });

    test('handover can not complete multiple times', () {
      final phase = TestPhase();
      phase.close(CloseCode.handover, 'foo');
      phase.notifyWsStreamClosed();
      expect(phase.io.sendEvents.isClosed, isFalse);
      expect(phase.handoverCallCount, equals(1));
      phase.io.expectEventOfType<HandoverToTask>();
      expect(phase.cancelTaskCallCount, equals(0));
      phase.notifyWsStreamClosed();
      expect(phase.io.sendEvents.isClosed, isFalse);
      expect(phase.handoverCallCount, equals(1));
      expect(phase.cancelTaskCallCount, equals(0));
      expect(phase.io.sendEvents, isEmpty);
    });

    test('server closes connection', () {
      final phase = TestPhase();
      final closeCode = CloseCode.initiatorCouldNotDecrypt.toInt();
      phase.webSocket.closeCode = closeCode;
      phase.notifyWsStreamClosed();
      expect(phase.webSocket.closeCode, equals(closeCode));
      phase.io.expectEventOfType<InitiatorCouldNotDecrypt>();
      expect(phase.cancelTaskCallCount, equals(1));
      expect(phase.io.sendEvents.isClosed, isTrue);
    });

    test('close events even if we start closing', () {
      final phase = TestPhase();
      final closeCode = CloseCode.initiatorCouldNotDecrypt;
      phase.close(closeCode, '');
      expect(phase.webSocket.closeCode, equals(closeCode.toInt()));
      phase.notifyWsStreamClosed();
      expect(phase.cancelTaskCallCount, equals(1));
      expect(phase.io.sendEvents.isClosed, isTrue);
    });
  });
}

class TestPhase extends Phase {
  int cancelTaskCallCount = 0;
  int closeMsgCallCount = 0;
  bool closeMsgWillBeSend = false;
  int handoverCallCount = 0;
  CloseCode? lastSendCloseCode;
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
    if (closeMsgWillBeSend) {
      lastSendCloseCode = closeCode;
    }
    return closeMsgWillBeSend;
  }

  @override
  void tellTaskThatHandoverCompleted() {
    handoverCallCount += 1;
  }
}
