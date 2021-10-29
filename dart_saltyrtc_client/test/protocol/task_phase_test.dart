import 'dart:collection' show Queue;
import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/src/crypto/crypto.dart'
    show InitialClientAuthMethod;
import 'package:dart_saltyrtc_client/src/messages/c2c/close.dart' show Close;
import 'package:dart_saltyrtc_client/src/messages/c2c/task_message.dart'
    show TaskMessage;
import 'package:dart_saltyrtc_client/src/messages/close_code.dart'
    show CloseCode, CloseCodeToFromInt;
import 'package:dart_saltyrtc_client/src/messages/id.dart' show Id;
import 'package:dart_saltyrtc_client/src/messages/s2c/disconnected.dart'
    show Disconnected;
import 'package:dart_saltyrtc_client/src/messages/s2c/new_initiator.dart'
    show NewInitiator;
import 'package:dart_saltyrtc_client/src/messages/s2c/new_responder.dart'
    show NewResponder;
import 'package:dart_saltyrtc_client/src/messages/s2c/send_error.dart'
    show SendError;
import 'package:dart_saltyrtc_client/src/protocol/events.dart'
    show
        AdditionalResponderEvent,
        Event,
        HandoverToTask,
        InternalError,
        PeerDisconnected,
        PeerKind;
import 'package:dart_saltyrtc_client/src/protocol/events.dart' as events;
import 'package:dart_saltyrtc_client/src/protocol/peer.dart'
    show Initiator, Peer, Responder;
import 'package:dart_saltyrtc_client/src/protocol/phases/client_handshake_initiator.dart'
    show InitiatorClientHandshakePhase;
import 'package:dart_saltyrtc_client/src/protocol/phases/client_handshake_responder.dart'
    show ResponderClientHandshakePhase, State;
import 'package:dart_saltyrtc_client/src/protocol/phases/phase.dart'
    show
        AfterServerHandshakePhase,
        Config,
        InitiatorConfig,
        Phase,
        ResponderConfig;
import 'package:dart_saltyrtc_client/src/protocol/phases/task.dart'
    show InitiatorTaskPhase, ResponderTaskPhase, TaskPhase;
import 'package:dart_saltyrtc_client/src/protocol/task.dart'
    show CancelReason, SaltyRtcTaskLink, Task;
import 'package:dart_saltyrtc_client/src/utils.dart' show Pair;
import 'package:test/test.dart';

import '../crypto_mock.dart' show crypto;
import '../network_mock.dart' show MockSyncWebSocketSink;
import '../utils.dart'
    show Io, PeerData, TestStep, createAfterServerHandshakeState, setUpTesting;
import '../utils.dart' as utils;
import 'phases/client_handshake_responder_test.dart'
    as c2c_handshake_responder_tests;

void main() {
  setUpTesting();

  for (final mkSetupPair in [
    Pair('initiator', () => InitiatorSetup.create()),
    Pair('responder', () => ResponderSetup.create()),
  ]) {
    final kind = mkSetupPair.first;
    final mkSetup = mkSetupPair.second;

    group(kind, () {
      test('start is called', () {
        final setup = mkSetup();
        setup.runTest([]);
      });

      test('messages are forwarded', () {
        final setup = mkSetup();
        setup.runTest([
          setup.mkRecvTaskMessageTest(type: 'taskMsg1', data: {'foo': 'bar'}),
        ]);
      });

      test('only registered task messages are forwarded', () {
        final setup = mkSetup();
        setup.runTest([
          setup.mkRecvBadTaskMessageTest(
              type: 'arbitraryMessage', data: {'foo': 'bar'}),
        ], skipCleanTest: true);
      });

      test('events are forwarded', () {
        final setup = mkSetup();
        setup.runTest([setup.mkRecvEventTest()]);
      });

      group('cancel is called on', () {
        test('disconnect', () {
          final setup = mkSetup();
          setup.runTest([setup.mkDisconnectTest()]);
        });

        test('send-error', () {
          final setup = mkSetup();
          setup.runTest([setup.mkSendErrorTest()]);
        });

        if (kind == 'initiator') {
          test('send-error unrelated', () {
            final setup = mkSetup() as InitiatorSetup;
            setup.runTest([setup.mkSendErrorUnrelatedTest()]);
          });
        }

        test('peer overwrite', () {
          final setup = mkSetup();
          setup.runTest([setup.mkPeerOverwriteTest()]);
        });
      });

      test('closing WS calls handleCancel ', () {
        final setup = mkSetup();
        setup.startPhase.common.webSocket.sink
            .close(CloseCode.noSharedSubprotocol.toInt(), 'a word');

        /// we have no client so we need fake the wiring
        setup.startPhase.notifyWsStreamClosed();
        expect(setup.task.handleCancelCallCount, equals(1));
        expect(setup.task.handleCancelReason,
            equals(CancelReason.serverDisconnected));
      });

      group('handover calls handleHandover when triggered by', () {
        test('link.handover()', () {
          final setup = mkSetup();
          setup.runTest([setup.mkTriggerHandoverTest()]);
        });

        test('Close(Handover) msg', () {
          final setup = mkSetup();
          setup.runTest([setup.mkRecvHandoverTest()]);
        });
      });

      group('task exceptions lead to internal error in', () {
        // Currently we can't test this without introducing a mechanism where
        // creating a phase doesn't automatically starts it.
        test('start', () {}, skip: true);

        test('handleMessage', () {
          final setup = mkSetup();
          setup.runTest([setup.mkPanicOnHandleMessageTest()]);
        });
        test('handleEvent', () {
          final setup = mkSetup();
          setup.runTest([setup.mkPanicOnHandleEventTest()]);
        });

        test('handleCancel', () {
          final setup = mkSetup();
          setup.runTest([setup.mkPanicOnHandleCancelTest()]);
        });
      });
    });
  }
}

class TestTask implements Task {
  @override
  late SaltyRtcTaskLink link;
  int startCallCount = 0;
  int handleCancelCallCount = 0;
  CancelReason? handleCancelReason;
  bool panicOnStart = false;
  bool panicOnHandleEvent = false;
  bool panicOnHandleMessage = false;
  bool panicOnHandleCancel = false;
  final Queue<TaskMessage> messages = Queue();
  final Queue<Event> events = Queue();

  @override
  void handleCancel(CancelReason reason) {
    handleCancelCallCount += 1;
    handleCancelReason = reason;
    if (panicOnHandleCancel) {
      throw Exception('planned panic on handleCancel');
    }
  }

  @override
  void handleEvent(Event event) {
    events.add(event);
    if (panicOnHandleEvent) {
      throw Exception('planned panic on handleEvent');
    }
  }

  @override
  void handleMessage(TaskMessage msg) {
    messages.add(msg);
    if (panicOnHandleMessage) {
      throw Exception('planned panic on handleMessage');
    }
  }

  @override
  void start() {
    startCallCount += 1;
    if (panicOnStart) {
      throw Exception('planned panic on start');
    }
  }

  @override
  List<String> get supportedTypes => ['taskMsg1', 'taskMsg2'];
}

abstract class Setup {
  final TestTask task;

  PeerData get peer;
  PeerData get server;
  Phase get startPhase;

  Setup(this.task);

  void runTest(List<Phase? Function(Phase, Io)> steps,
      {bool skipCleanTest = false}) {
    final allSteps = [mkStartHasBeenCalledTest()];
    allSteps.addAll(steps);
    if (!skipCleanTest) {
      allSteps.add(mkTaskIsCleanTest());
    }
    utils.runTest(startPhase, allSteps);
  }

  TestStep mkStartHasBeenCalledTest() {
    return (phase, io) {
      expect(task.startCallCount, equals(1));
      return phase;
    };
  }

  TestStep mkTaskIsCleanTest() {
    return (phase, io) {
      expect(task.messages, isEmpty);
      expect(task.events, isEmpty);
      return phase;
    };
  }

  TestStep mkRecvTaskMessageTest({
    required String type,
    required Map<String, Object?> data,
  }) {
    return (initialPhase, io) {
      final phase = peer.sendAndTransitToPhase<TaskPhase>(
          message: TaskMessage(type, data),
          sendTo: initialPhase,
          encryptWith: crypto.createSharedKeyStore(
              ownKeyStore: peer.testedPeer.ourSessionKey!,
              remotePublicKey: peer.testedPeer.theirSessionKey!.publicKey));

      final msg = task.messages.removeFirst();
      expect(msg.type, equals(type));
      expect(msg.data, equals(data));
      expect(task.messages, isEmpty);
      return phase;
    };
  }

  TestStep mkRecvBadTaskMessageTest({
    required String type,
    required Map<String, Object?> data,
  }) {
    return (initialPhase, io) {
      final closeCode = peer.sendAndClose(
          message: TaskMessage(type, data),
          sendTo: initialPhase,
          encryptWith: crypto.createSharedKeyStore(
              ownKeyStore: peer.testedPeer.ourSessionKey!,
              remotePublicKey: peer.testedPeer.theirSessionKey!.publicKey));

      expect(task.messages, isEmpty);
      expect(closeCode, equals(CloseCode.goingAway.toInt()));
      expect(initialPhase.isClosingWsStream, isTrue);
      final closeMsg = io.expectMessageOfType<Close>(
          sendTo: peer,
          decryptWith: crypto.createSharedKeyStore(
              ownKeyStore: peer.testedPeer.ourSessionKey!,
              remotePublicKey: peer.testedPeer.theirSessionKey!.publicKey));
      expect(closeMsg.reason, equals(CloseCode.protocolError));
      final event = io.expectEventOfType<events.ProtocolErrorWithPeer>();
      expect(event.peerKind, equals(PeerKind.authenticated));
      return null;
    };
  }

  TestStep mkRecvEventTest() {
    return (initialPhase, io) {
      // ignore: invalid_use_of_protected_member
      initialPhase.emitEvent(events.AdditionalResponderEvent(
          events.PeerDisconnected(PeerKind.unauthenticated)));

      final event = task.events.removeFirst();
      expect(event, isA<events.AdditionalResponderEvent>());
      io.expectEventOfType<events.AdditionalResponderEvent>();
      return initialPhase;
    };
  }

  TestStep mkDisconnectTest() {
    return (initialPhase, io) {
      final phase = server.sendAndTransitToPhase<AfterServerHandshakePhase>(
          message: Disconnected(peer.address.asClient()),
          sendTo: initialPhase,
          encryptWith: crypto.createSharedKeyStore(
              ownKeyStore: server.testedPeer.ourSessionKey!,
              remotePublicKey: server.testedPeer.permanentKey!.publicKey));
      final event = io.expectEventOfType<events.PeerDisconnected>();
      expect(event.peerKind, PeerKind.authenticated);
      expect(task.handleCancelCallCount, equals(1));
      expect(task.handleCancelReason, equals(CancelReason.peerUnavailable));
      expect(task.events.removeLast(),
          equals(events.PeerDisconnected(PeerKind.authenticated)));
      return phase;
    };
  }

  TestStep mkSendErrorTest() {
    return (initialPhase, io) {
      final phase = server.sendAndTransitToPhase<AfterServerHandshakePhase>(
          message: SendError(Uint8List.fromList([
            initialPhase.common.address.value,
            peer.address.value,
            0,
            0,
            0,
            0,
            0,
            0
          ])),
          sendTo: initialPhase,
          encryptWith: crypto.createSharedKeyStore(
              ownKeyStore: server.testedPeer.ourSessionKey!,
              remotePublicKey: server.testedPeer.permanentKey!.publicKey));
      final event = io.expectEventOfType<events.SendingMessageToPeerFailed>();
      expect(event.peerKind, PeerKind.authenticated);
      expect(task.handleCancelCallCount, equals(1));
      expect(task.handleCancelReason, equals(CancelReason.peerUnavailable));
      expect(task.events.removeLast(),
          equals(events.SendingMessageToPeerFailed(PeerKind.authenticated)));
      return phase;
    };
  }

  TestStep mkTriggerHandoverTest() {
    return (phase, io) {
      task.link.requestHandover();
      expect(phase.isClosingWsStream, isTrue);
      expect((phase.common.webSocket.sink as MockSyncWebSocketSink).closeCode,
          equals(CloseCode.goingAway.toInt()));
      final closeMsg = io.expectMessageOfType<Close>(
        sendTo: peer,
        decryptWith: crypto.createSharedKeyStore(
          ownKeyStore: peer.testedPeer.ourSessionKey!,
          remotePublicKey: peer.testedPeer.theirSessionKey!.publicKey,
        ),
      );
      expect(closeMsg.reason, equals(CloseCode.handover));
      expect(io.sendEvents, isEmpty);

      phase.notifyWsStreamClosed();
      io.expectEventOfType<HandoverToTask>();

      expect(task.events.removeLast(), equals(HandoverToTask()));

      return phase;
    };
  }

  TestStep mkRecvHandoverTest() {
    return (initialPhase, io) {
      final closeCode = peer.sendAndClose(
        message: Close(CloseCode.handover),
        sendTo: initialPhase,
        encryptWith: crypto.createSharedKeyStore(
          ownKeyStore: peer.testedPeer.ourSessionKey!,
          remotePublicKey: peer.testedPeer.theirSessionKey!.publicKey,
        ),
      );
      expect(closeCode, equals(CloseCode.goingAway.toInt()));

      initialPhase.notifyWsStreamClosed();
      io.expectEventOfType<HandoverToTask>();
      expect(task.events.removeLast(), equals(HandoverToTask()));
      return initialPhase;
    };
  }

  TestStep mkPanicOnHandleMessageTest() {
    return (phase, io) {
      task.panicOnHandleMessage = true;
      final closeCode = peer.sendAndClose(
        message: TaskMessage('taskMsg1', {}),
        sendTo: phase,
        encryptWith: crypto.createSharedKeyStore(
          ownKeyStore: peer.testedPeer.ourSessionKey!,
          remotePublicKey: peer.testedPeer.theirSessionKey!.publicKey,
        ),
      );
      final event = io.expectEventOfType<InternalError>();
      expect(event.error.toString(), contains('handleMessage'));
      expect(task.events, isEmpty);
      expect(closeCode, equals(CloseCode.goingAway.toInt()));
      final closeMsg = io.expectMessageOfType<Close>(
        sendTo: peer,
        decryptWith: crypto.createSharedKeyStore(
          ownKeyStore: peer.testedPeer.ourSessionKey!,
          remotePublicKey: peer.testedPeer.theirSessionKey!.publicKey,
        ),
      );
      expect(closeMsg.reason, equals(CloseCode.internalError));
      expect(task.messages.removeLast(), TaskMessage('taskMsg1', {}));
      return phase;
    };
  }

  TestStep mkPanicOnHandleEventTest() {
    return (phase, io) {
      task.panicOnHandleEvent = true;
      final eventToEmit =
          AdditionalResponderEvent(PeerDisconnected(PeerKind.unauthenticated));
      phase.emitEvent(eventToEmit);
      // event is emitted first
      io.expectEventOfType<AdditionalResponderEvent>();
      final event = io.expectEventOfType<InternalError>();
      expect(event.error.toString(), contains('handleEvent'));
      expect(task.messages, isEmpty);
      expect((phase.common.webSocket.sink as MockSyncWebSocketSink).closeCode,
          equals(CloseCode.goingAway.toInt()));
      final closeMsg = io.expectMessageOfType<Close>(
        sendTo: peer,
        decryptWith: crypto.createSharedKeyStore(
          ownKeyStore: peer.testedPeer.ourSessionKey!,
          remotePublicKey: peer.testedPeer.theirSessionKey!.publicKey,
        ),
      );
      expect(closeMsg.reason, equals(CloseCode.internalError));
      expect(task.events.removeLast(), eventToEmit);
      return phase;
    };
  }

  TestStep mkPanicOnHandleCancelTest() {
    return (phase, io) {
      task.panicOnHandleCancel = true;
      final closeCode = server.sendAndClose(
        message: Disconnected(peer.address.asClient()),
        sendTo: phase,
        encryptWith: crypto.createSharedKeyStore(
          ownKeyStore: server.testedPeer.ourSessionKey!,
          remotePublicKey: server.testedPeer.permanentKey!.publicKey,
        ),
      );
      final disconnectedEvent = io.expectEventOfType<PeerDisconnected>();
      expect(disconnectedEvent.peerKind, PeerKind.authenticated);
      final errorEvent = io.expectEventOfType<InternalError>();
      expect(errorEvent.error.toString(), contains('handleCancel'));
      expect(closeCode, equals(CloseCode.goingAway.toInt()));
      expect(task.messages, isEmpty);
      expect(
          task.events.removeLast(), PeerDisconnected(PeerKind.authenticated));
      expect(task.events, isEmpty);
      final closeMsg = io.expectMessageOfType<Close>(
        sendTo: peer,
        decryptWith: crypto.createSharedKeyStore(
          ownKeyStore: peer.testedPeer.ourSessionKey!,
          remotePublicKey: peer.testedPeer.theirSessionKey!.publicKey,
        ),
      );
      expect(closeMsg.reason, equals(CloseCode.internalError));
      return phase;
    };
  }

  TestStep mkPeerOverwriteTest();
}

class InitiatorSetup extends Setup {
  @override
  final InitiatorTaskPhase startPhase;
  @override
  final PeerData server;
  final PeerData responder;

  @override
  PeerData get peer => responder;

  InitiatorSetup._(TestTask task, this.startPhase, this.server, this.responder)
      : super(task);

  factory InitiatorSetup.create() {
    final task = TestTask();
    final responderId = Id.responderId(32);
    final pair = createAfterServerHandshakeState(Id.initiatorAddress);
    final server = pair.first;
    final initiatorCommon = pair.second;
    final config = InitiatorConfig(
        authMethod: InitialClientAuthMethod.fromEither(
            authToken: crypto.createAuthToken()),
        expectedServerPublicKey: server.permanentKey.publicKey,
        permanentKeys: crypto.createKeyStore(),
        tasks: []);

    final responder =
        PeerData(address: responderId, testedPeerId: Id.initiatorAddress);
    final initiatorResponderKnowledge = Responder(responderId, crypto);

    syncPeeringState(
      knowledgeAboutPeer: initiatorResponderKnowledge,
      config: config,
      peer: responder,
      idOfPeer: responderId,
      ifOfTestedClient: Id.initiatorAddress,
    );

    final phase = InitiatorTaskPhase(initiatorCommon, config,
        initiatorResponderKnowledge.assertAuthenticated(), task);

    return InitiatorSetup._(task, phase, server, responder);
  }

  TestStep mkSendErrorUnrelatedTest() {
    return (initialPhase, io) {
      final phase = server.sendAndTransitToPhase(
          message: SendError(Uint8List.fromList([
            initialPhase.common.address.value,
            Id.responderId(120).value,
            0,
            0,
            0,
            0,
            0,
            0
          ])),
          sendTo: initialPhase,
          encryptWith: crypto.createSharedKeyStore(
              ownKeyStore: server.testedPeer.ourSessionKey!,
              remotePublicKey: server.testedPeer.permanentKey!.publicKey));
      expect(phase, same(initialPhase));
      final event =
          io.expectEventOfType<events.AdditionalResponderEvent>().event;
      expect(event, isA<events.SendingMessageToPeerFailed>());
      expect((event as events.SendingMessageToPeerFailed).peerKind,
          PeerKind.unauthenticated);
      expect(task.handleCancelCallCount, equals(0));
      expect(
          task.events.removeLast(),
          equals(events.AdditionalResponderEvent(
              events.SendingMessageToPeerFailed(PeerKind.unauthenticated))));
      return phase;
    };
  }

  @override
  TestStep mkPeerOverwriteTest() {
    return (initialPhase, io) {
      final phase = server.sendAndTransitToPhase<InitiatorClientHandshakePhase>(
          message: NewResponder(peer.address.asResponder()),
          sendTo: initialPhase,
          encryptWith: crypto.createSharedKeyStore(
              ownKeyStore: server.testedPeer.ourSessionKey!,
              remotePublicKey: server.testedPeer.permanentKey!.publicKey));
      final event = io.expectEventOfType<events.PeerDisconnected>();
      expect(event.peerKind, PeerKind.authenticated);
      expect(task.handleCancelCallCount, equals(1));
      expect(task.handleCancelReason, equals(CancelReason.peerOverwrite));
      expect(task.events.removeLast(),
          equals(events.PeerDisconnected(PeerKind.authenticated)));
      expect(phase.responders.keys, contains(peer.address));
      expect(phase.responders[peer.address]!.receivedAnyMessage, isFalse);
      return phase;
    };
  }
}

class ResponderSetup extends Setup {
  @override
  final ResponderTaskPhase startPhase;
  @override
  final PeerData server;
  final PeerData initiator;

  @override
  PeerData get peer => initiator;

  ResponderSetup._(TestTask task, this.startPhase, this.server, this.initiator)
      : super(task);

  factory ResponderSetup.create() {
    final task = TestTask();
    final responderId = Id.responderId(32);
    final pair = createAfterServerHandshakeState(responderId);
    final server = pair.first;
    final responderCommon = pair.second;
    final authToken = crypto.createAuthToken();
    final initiator = PeerData(
      address: Id.initiatorAddress,
      testedPeerId: responderId,
      authToken: authToken,
    );
    final config = ResponderConfig(
      authToken: authToken,
      expectedServerPublicKey: server.permanentKey.publicKey,
      permanentKeys: crypto.createKeyStore(),
      tasks: [],
      initiatorPermanentPublicKey: initiator.permanentKey.publicKey,
    );

    final respondersInitiatorKnowledge = Initiator(crypto);

    syncPeeringState(
      knowledgeAboutPeer: respondersInitiatorKnowledge,
      config: config,
      peer: initiator,
      idOfPeer: Id.initiatorAddress,
      ifOfTestedClient: responderId,
    );

    final phase = ResponderTaskPhase(responderCommon, config,
        respondersInitiatorKnowledge.assertAuthenticated(), task);

    return ResponderSetup._(task, phase, server, initiator);
  }

  @override
  TestStep mkPeerOverwriteTest() {
    final restartC2CHandshakeTest =
        c2c_handshake_responder_tests.mkRecvTokenAndKeyTest(initiator);
    return (initialPhase, io) {
      final phase = server.sendAndTransitToPhase<ResponderClientHandshakePhase>(
          message: NewInitiator(),
          sendTo: initialPhase,
          encryptWith: crypto.createSharedKeyStore(
              ownKeyStore: server.testedPeer.ourSessionKey!,
              remotePublicKey: server.testedPeer.permanentKey!.publicKey));
      final event = io.expectEventOfType<events.PeerDisconnected>();
      expect(event.peerKind, PeerKind.authenticated);
      expect(task.handleCancelCallCount, equals(1));
      expect(task.handleCancelReason, equals(CancelReason.peerOverwrite));
      expect(task.events.removeLast(),
          equals(events.PeerDisconnected(PeerKind.authenticated)));
      expect(phase.initiatorWithState, isNotNull);
      expect(phase.initiatorWithState!.state, equals(State.waitForKeyMsg));
      initiator.resetTestedClientKnowledge();
      return restartC2CHandshakeTest(phase, io);
    };
  }
}

void syncPeeringState({
  required Peer knowledgeAboutPeer,
  required Config config,
  required PeerData peer,
  required Id idOfPeer,
  required Id ifOfTestedClient,
}) {
  // sync permanent and session keys
  knowledgeAboutPeer.setPermanentSharedKey(crypto.createSharedKeyStore(
      ownKeyStore: config.permanentKey,
      remotePublicKey: peer.permanentKey.publicKey));
  peer.testedPeer.theirSessionKey = crypto.createKeyStore();
  peer.testedPeer.ourSessionKey = crypto.createKeyStore();
  knowledgeAboutPeer.setSessionSharedKey(crypto.createSharedKeyStore(
      ownKeyStore: peer.testedPeer.theirSessionKey!,
      remotePublicKey: peer.testedPeer.ourSessionKey!.privateKey));
  // sync cookiePair
  knowledgeAboutPeer.cookiePair
      .updateAndCheck(peer.testedPeer.cookiePair.ours, idOfPeer);
  peer.testedPeer.cookiePair
      .updateAndCheck(knowledgeAboutPeer.cookiePair.ours, ifOfTestedClient);
  // sync csPair
  knowledgeAboutPeer.csPair
      .updateAndCheck(peer.testedPeer.csPair.ours, idOfPeer);
  peer.testedPeer.csPair
      .updateAndCheck(knowledgeAboutPeer.csPair.ours, ifOfTestedClient);
}
