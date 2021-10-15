import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/src/closer.dart' show Closer;
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
      void theTest(CloseCode? closeCode, int? closeCode2) {
        final tests = <Function()>[];
        final phase = TestPhase(doCloseFn: (closeCode, phase) {
          tests.add(() {
            expect(closeCode, equals(closeCode));
          });
          return closeCode2;
        });
        phase.common.closer.close(closeCode, 'foo');
        tests.removeLast()();
        expect(tests, isEmpty);
        expect(phase.webSocket.isClosed, isTrue);
        expect(phase.webSocket.closeCode, equals(closeCode2));
        expect(phase.io.sendEvents, isEmpty);
      }

      theTest(CloseCode.invalidKey, CloseCode.goingAway.toInt());
      theTest(CloseCode.invalidKey, null);
      theTest(null, CloseCode.goingAway.toInt());
      theTest(null, null);
    });
    test(
        'if phase.doClose throws a InternalError even is emitted and internalError is used as close code',
        () {
      final phase = TestPhase(doCloseFn: (closeCode, phase) {
        throw StateError('foo bar');
      });
      phase.common.closer.close(CloseCode.closingNormal, 'lala');
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
      phase.common.closer.close(CloseCode.goingAway, 'a');
      phase.common.closer.close(CloseCode.internalError, 'b');
      phase.common.closer.close(CloseCode.invalidKey, 'c');
      expect(callCount, equals(1));
    });

    test('sets isClosing before calling doClose', () {
      bool? isClosed;
      final phase = TestPhase(doCloseFn: (closeCode, phase) {
        isClosed = phase.common.closer.isClosing;
      });
      phase.common.closer.close(CloseCode.closingNormal, 'lala');
      expect(isClosed, isTrue);
      expect(phase.common.closer.isClosing, isTrue);
    });
  });

  group('notifyConnectionClosed', () {
    test('sets isClosed immediately but does not call doClose', () async {
      bool called = false;
      final phase = TestPhase(doCloseFn: (closeCode, phase) {
        called = true;
      });
      await phase.common.sink.close(CloseCode.closingNormal.toInt());
      phase.common.closer.notifyConnectionClosed();
      expect(called, isFalse);
      expect(phase.common.closer.isClosing, isTrue);
      await phase.common.closer.onClosed;
      expect(called, isFalse);
      expect(phase.common.closer.isClosing, isTrue);
    });

    test('if not manually closed close the events and maybe emits a Event',
        () async {
      var phase = TestPhase();
      await phase.common.sink.close(CloseCode.initiatorCouldNotDecrypt.toInt());
      phase.common.closer.notifyConnectionClosed();
      await phase.common.closer.onClosed;
      phase.io.expectEventOfType<InitiatorCouldNotDecrypt>();
      expect(phase.common.closer.isClosing, isTrue);
      expect(phase.io.sendEvents.isClosed, isTrue);

      phase = TestPhase();
      await phase.common.sink.close(CloseCode.closingNormal.toInt());
      phase.common.closer.notifyConnectionClosed();
      await phase.common.closer.onClosed;
      expect(phase.io.sendEvents, isEmpty);
      expect(phase.common.closer.isClosing, isTrue);
      expect(phase.io.sendEvents.isClosed, isTrue);
    });

    test('if manually closed do not emit event but still close events',
        () async {
      final phase = TestPhase();
      phase.common.closer.close(CloseCode.initiatorCouldNotDecrypt, 'foo');
      expect(phase.common.closer.isClosing, isTrue);
      expect(phase.io.sendEvents.isClosed, isFalse);
      phase.common.closer.notifyConnectionClosed();
      await phase.common.closer.onClosed;
      expect(phase.common.closer.isClosing, isTrue);
      expect(phase.io.sendEvents.isClosed, isTrue);
    });

    test('runs only once', () async {
      var counter = 0;
      final phase = TestPhase();
      final closed = phase.common.closer.onClosed.whenComplete(() {
        counter += 1;
      });
      await phase.webSocket.sink.close(CloseCode.goingAway.toInt());
      phase.common.closer.notifyConnectionClosed();
      expect(() {
        phase.common.closer.notifyConnectionClosed();
      }, throwsA(isA<StateError>()));
      await closed;
      expect(counter, equals(1));
    });
  });

  test('handover closes the WS but not events', () async {
    Function()? doCloseTest;
    final phase = TestPhase(doCloseFn: (closeCode, phase) {
      doCloseTest = () {
        expect(closeCode, equals(CloseCode.handover));
      };
      return CloseCode.goingAway.toInt();
    });
    phase.common.closer.enableHandover = true;
    phase.common.closer.close(CloseCode.handover, 'handover');
    phase.common.closer.notifyConnectionClosed();
    expect(phase.webSocket.isClosed, isTrue);
    expect(phase.webSocket.closeCode, equals(CloseCode.goingAway.toInt()));
    doCloseTest!();
    phase.io.expectEventOfType<HandoverToTask>();
    expect(phase.io.sendEvents.isClosed, isFalse);
    await phase.common.closer.onClosed;
    expect(phase.io.sendEvents.isClosed, isFalse);
  });
}

class TestPhase implements Phase {
  final MockSyncWebSocket webSocket = MockSyncWebSocket();
  late Io io = Io(PackageQueue(), EventQueue());
  @override
  late InitialCommon common =
      InitialCommon(crypto, webSocket.sink, io.sendEvents, Closer(webSocket));

  final int? Function(CloseCode?, TestPhase) _doCloseFn;

  TestPhase({int? Function(CloseCode?, TestPhase)? doCloseFn})
      : _doCloseFn = doCloseFn ?? ((closeCode, phase) => closeCode?.toInt()) {
    common.closer.setCurrentPhase(this);
  }

  @override
  Uint8List buildPacket(Message msg, Peer receiver,
          {bool encrypt = true, AuthToken? authToken}) =>
      throw UnimplementedError();

  @override
  Config get config => throw UnimplementedError();

  @override
  int? doClose(CloseCode? closeCode) => _doCloseFn(closeCode, this);

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
}
