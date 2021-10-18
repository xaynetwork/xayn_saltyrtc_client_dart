import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/src/crypto/crypto.dart' show AuthToken;
import 'package:dart_saltyrtc_client/src/messages/c2c/auth_initiator.dart'
    show AuthInitiator;
import 'package:dart_saltyrtc_client/src/messages/c2c/auth_responder.dart'
    show AuthResponder;
import 'package:dart_saltyrtc_client/src/messages/c2c/close.dart' show Close;
import 'package:dart_saltyrtc_client/src/messages/c2c/key.dart' show Key;
import 'package:dart_saltyrtc_client/src/messages/c2c/token.dart' show Token;
import 'package:dart_saltyrtc_client/src/messages/close_code.dart'
    show CloseCode;
import 'package:dart_saltyrtc_client/src/messages/id.dart' show Id;
import 'package:dart_saltyrtc_client/src/messages/message.dart' show TasksData;
import 'package:dart_saltyrtc_client/src/messages/s2c/disconnected.dart'
    show Disconnected;
import 'package:dart_saltyrtc_client/src/messages/s2c/new_initiator.dart'
    show NewInitiator;
import 'package:dart_saltyrtc_client/src/messages/s2c/send_error.dart'
    show SendError;
import 'package:dart_saltyrtc_client/src/protocol/events.dart' as events;
import 'package:dart_saltyrtc_client/src/protocol/phases/client_handshake_responder.dart'
    show ResponderClientHandshakePhase, State;
import 'package:dart_saltyrtc_client/src/protocol/phases/phase.dart'
    show Phase, ResponderConfig;
import 'package:dart_saltyrtc_client/src/protocol/phases/task.dart'
    show ResponderTaskPhase;
import 'package:dart_saltyrtc_client/src/protocol/task.dart' show TaskBuilder;
import 'package:test/test.dart';

import '../../crypto_mock.dart' show crypto;
import '../../network_mock.dart' show EventQueue;
import '../../utils.dart'
    show
        Io,
        PeerData,
        TestTask,
        TestTaskBuilder,
        createAfterServerHandshakeState,
        phaseAs,
        runTest,
        setUpTesting;

void main() {
  setUpTesting();

  group('successful transition', () {
    test('key+token are send out on creation', () {
      final setup = _Setup.create();
      runTest(setup.initialPhase, [mkRecvTokenAndKeyTest(setup.initiator)]);
    });
    test('key is send out on creation', () {
      final setup = _Setup.create(usePresetTrust: true);
      runTest(setup.initialPhase, [mkRecvKeyTest(setup.initiator)]);
    });

    test('initiator connects later', () {
      final setup = _Setup.create(initiatorIsKnown: false);
      runTest(setup.initialPhase, [
        (phase, io) {
          // check that initiating didn't send any packages or events
          expect(io.sendPackages, isEmpty);
          expect(io.sendEvents, isEmpty);
          return phase;
        },
        mkNewInitiatorTest(initiator: setup.initiator, server: setup.server),
      ]);
    });

    test('initiator sends key', () {
      final tasks = [
        TestTaskBuilder('bar foot'),
        TestTaskBuilder('bar'),
        TestTaskBuilder('example.v23')
      ];
      final setup = _Setup.create(usePresetTrust: true, tasks: tasks);
      final initiator = setup.initiator;
      runTest(setup.initialPhase, [
        mkRecvKeyTest(initiator),
        mkSendKeyRecvAuthTest(
          initiator: initiator,
          tasks: tasks,
        ),
      ]);
    });

    test('initiator sends auth', () {
      final tasks = [TestTaskBuilder('example.v23')];
      final setup = _Setup.create(usePresetTrust: true, tasks: tasks);
      final initiator = setup.initiator;
      runTest(setup.initialPhase, [
        mkRecvKeyTest(initiator),
        mkSendKeyRecvAuthTest(
          initiator: initiator,
          tasks: tasks,
        ),
        mkSendAuthTest(initiator: initiator, task: 'example.v23', data: {
          'example.v23': {
            'foo': [1]
          }
        }),
      ]);
    });
  });

  test('protocol error', () {
    final setup = _Setup.create();
    final initiator = setup.initiator;
    runTest(setup.initialPhase, [
      mkRecvTokenAndKeyTest(initiator),
      (initialPhase, io) {
        final closeCode = initiator.sendAndClose(
          message: Token(crypto.createAuthToken().bytes),
          sendTo: initialPhase,
          encryptWith: crypto.createSharedKeyStore(
            ownKeyStore: initiator.permanentKey,
            remotePublicKey: initiator.testedPeer.permanentKey!.publicKey,
          ),
        );
        expect(closeCode, equals(CloseCode.goingAway));
        final event = io.expectEventOfType<events.ProtocolErrorWithPeer>();
        expect(event.peerKind, events.PeerKind.unauthenticated);
        return null;
      }
    ]);
  });

  test('auth -> no task found', () {
    final tasks = [TestTaskBuilder('example.v23')];
    final setup = _Setup.create(usePresetTrust: true, tasks: tasks);
    final initiator = setup.initiator;
    runTest(setup.initialPhase, [
      mkRecvKeyTest(initiator),
      mkSendKeyRecvAuthTest(
        initiator: initiator,
        tasks: tasks,
      ),
      mkSendNoSharedTaskTest(initiator),
    ]);
  });

  test('handleDisconnected', () {
    final setup = _Setup.create(usePresetTrust: true);
    runTest(setup.initialPhase, [
      mkRecvKeyTest(setup.initiator),
      mkInitiatorDisconnectedTest(server: setup.server),
    ]);
  });

  test('initiator override', () {
    final setup = _Setup.create();
    runTest(setup.initialPhase, [
      mkRecvTokenAndKeyTest(setup.initiator),
      mkNewInitiatorTest(initiator: setup.initiator, server: setup.server),
    ]);
  });

  test('handle SendError', () {
    final tasks = [TestTaskBuilder('example.v23')];
    final setup = _Setup.create(tasks: tasks);
    final initiator = setup.initiator;
    final server = setup.server;
    runTest(setup.initialPhase, [
      mkRecvTokenAndKeyTest(initiator),
      mkSendErrorTest(server: setup.server, initiator: initiator),
      mkNewInitiatorTest(initiator: initiator, server: server),
      mkSendKeyRecvAuthTest(
        initiator: initiator,
        tasks: tasks,
      ),
      mkSendAuthTest(initiator: initiator, task: 'example.v23', data: {
        'example.v23': {
          'foo': [1]
        }
      }),
    ]);
  });

  test('auth your_cookie is checked', () {
    final tasks = [TestTaskBuilder('example.v23')];
    final setup = _Setup.create(usePresetTrust: true, tasks: tasks);
    final initiator = setup.initiator;
    runTest(setup.initialPhase, [
      mkRecvKeyTest(initiator),
      mkSendKeyRecvAuthTest(
        initiator: initiator,
        tasks: tasks,
      ),
      (initialPhase, io) {
        final closeCode = initiator.sendAndClose(
          message: AuthInitiator(initiator.testedPeer.cookiePair.ours,
              'example.v23', {'example.v23': null}),
          sendTo: initialPhase,
          encryptWith: crypto.createSharedKeyStore(
              ownKeyStore: initiator.testedPeer.ourSessionKey!,
              remotePublicKey: initiator.testedPeer.theirSessionKey!.publicKey),
        );

        expect(closeCode, equals(CloseCode.goingAway));
        final event = io.expectEventOfType<events.ProtocolErrorWithPeer>();
        expect(event.peerKind, events.PeerKind.unauthenticated);
        return null;
      }
    ]);
  });
}

class _Setup {
  final PeerData server;
  final PeerData initiator;
  final ResponderClientHandshakePhase initialPhase;
  final EventQueue events;

  _Setup({
    required this.server,
    required this.initiator,
    required this.initialPhase,
    required this.events,
  });

  factory _Setup.create({
    bool usePresetTrust = false,
    bool badInitialAuth = false,
    bool initiatorIsKnown = true,
    List<TaskBuilder>? tasks,
  }) {
    final responderId = Id.responderId(32);
    final sAndC = createAfterServerHandshakeState(crypto, responderId);
    final server = sAndC.first;
    final common = sAndC.second;
    final responderPermanentKey = server.testedPeer.permanentKey!;

    AuthToken? authToken;
    if (!usePresetTrust) {
      authToken = crypto.createAuthToken();
    }

    final initiator = PeerData(
      address: Id.initiatorAddress,
      testedPeerId: responderId,
      authToken: badInitialAuth ? crypto.createAuthToken() : authToken,
    );
    if (usePresetTrust) {
      initiator.testedPeer.permanentKey = responderPermanentKey;
    }

    final config = ResponderConfig(
      permanentKeys: responderPermanentKey,
      tasks: tasks ?? [],
      initiatorPermanentPublicKey: initiator.permanentKey.publicKey,
      authToken: authToken,
      expectedServerPublicKey: server.permanentKey.publicKey,
    );

    final phase = ResponderClientHandshakePhase(
      common,
      config,
      initiatorConnected: initiatorIsKnown,
    );

    return _Setup(
      server: server,
      initiator: initiator,
      initialPhase: phase,
      events: common.events as EventQueue,
    );
  }
}

Phase? Function(Phase, Io) mkRecvTokenAndKeyTest(PeerData initiator) {
  final keyTest = mkRecvKeyTest(initiator);
  return (initialPhase, io) {
    final phase = phaseAs<ResponderClientHandshakePhase>(initialPhase);

    final tokenMsg = io.expectMessageOfType<Token>(
        sendTo: initiator, decryptWith: initiator.authToken);

    expect(tokenMsg.key, equals(initialPhase.config.permanentKey.publicKey));
    initiator.testedPeer.permanentKey = initialPhase.config.permanentKey;

    return keyTest(phase, io);
  };
}

Phase? Function(Phase, Io) mkRecvKeyTest(PeerData initiator) {
  return (initialPhase, io) {
    final keyMsg = io.expectMessageOfType<Key>(
        sendTo: initiator,
        decryptWith: crypto.createSharedKeyStore(
            ownKeyStore: initiator.permanentKey,
            remotePublicKey: initiator.testedPeer.permanentKey!.publicKey));

    final phase = phaseAs<ResponderClientHandshakePhase>(initialPhase);
    expect(keyMsg.key, equals(phase.initiatorWithState!.sessionKey.publicKey));

    // At this state we should know nothing about the initiator (except it's
    // permanent public key).
    expect(phase.initiatorWithState, isNotNull);
    expect(phase.initiatorWithState!.state, State.waitForKeyMsg);
    final initiatorFromResponder = phase.initiatorWithState!.initiator;
    expect(initiatorFromResponder.cookiePair.theirs, isNull);
    expect(initiatorFromResponder.csPair.theirs, isNull);
    expect(initiatorFromResponder.permanentSharedKey, isNotNull);

    return phase;
  };
}

Phase? Function(Phase, Io) mkNewInitiatorTest({
  required PeerData initiator,
  required PeerData server,
}) {
  final tokenAndKeyTest = mkRecvTokenAndKeyTest(initiator);
  return (initialPhase, io) {
    final phase = server.sendAndTransitToPhase<ResponderClientHandshakePhase>(
        message: NewInitiator(),
        sendTo: initialPhase,
        encryptWith: crypto.createSharedKeyStore(
          ownKeyStore: server.testedPeer.ourSessionKey!,
          remotePublicKey: server.testedPeer.permanentKey!.publicKey,
        ));

    expect(phase.initiatorWithState, isNotNull);
    expect(phase.initiatorWithState!.state, State.waitForKeyMsg);
    final initiatorFromResponder = phase.initiatorWithState!.initiator;
    expect(initiatorFromResponder.cookiePair.theirs, isNull);
    expect(initiatorFromResponder.csPair.theirs, isNull);
    expect(initiatorFromResponder.permanentSharedKey, isNotNull);

    resetInitiatorData(initiator);

    return tokenAndKeyTest(phase, io);
  };
}

Phase? Function(Phase, Io) mkSendKeyRecvAuthTest({
  required PeerData initiator,
  required List<TaskBuilder> tasks,
}) {
  return (initialPhase, io) {
    final sessionKey = crypto.createKeyStore();
    initiator.testedPeer.ourSessionKey = sessionKey;
    final phase =
        initiator.sendAndTransitToPhase<ResponderClientHandshakePhase>(
            message: Key(sessionKey.publicKey),
            sendTo: initialPhase,
            encryptWith: crypto.createSharedKeyStore(
              ownKeyStore: initiator.permanentKey,
              remotePublicKey: initiator.testedPeer.permanentKey!.publicKey,
            ));

    expect(phase.initiatorWithState, isNotNull);
    expect(phase.initiatorWithState!.state, State.waitForAuth);
    initiator.testedPeer.theirSessionKey = phase.initiatorWithState!.sessionKey;
    final sessionSharedKey = crypto.createSharedKeyStore(
      ownKeyStore: phase.initiatorWithState!.sessionKey,
      remotePublicKey: sessionKey.publicKey,
    );
    expect(phase.initiatorWithState!.initiator.sessionSharedKey,
        same(sessionSharedKey));

    final authMsg = io.expectMessageOfType<AuthResponder>(
        sendTo: initiator, decryptWith: sessionSharedKey);

    expect(authMsg.yourCookie, equals(initiator.testedPeer.cookiePair.ours));
    final taskData = {
      for (final task in tasks) task.name: task.getInitialResponderData()
    };
    expect(authMsg.tasks, equals(taskData.keys));
    expect(authMsg.data, equals(taskData));
    return phase;
  };
}

Phase? Function(Phase, Io) mkSendAuthTest({
  required PeerData initiator,
  required String task,
  required TasksData data,
}) {
  return (initialPhase, io) {
    final phase = initiator.sendAndTransitToPhase<ResponderTaskPhase>(
      message:
          AuthInitiator(initiator.testedPeer.cookiePair.theirs!, task, data),
      sendTo: initialPhase,
      encryptWith: crypto.createSharedKeyStore(
          ownKeyStore: initiator.testedPeer.ourSessionKey!,
          remotePublicKey: initiator.testedPeer.theirSessionKey!.publicKey),
    );

    expect(phase.pairedClient.permanentSharedKey.remotePublicKey,
        equals(initiator.permanentKey.publicKey));

    final taskObject = phase.task as TestTask;
    expect(taskObject.name, equals(task));
    expect(taskObject.initData, equals(data[taskObject.name]));

    final authEvent = io.expectEventOfType<events.ResponderAuthenticated>();
    expect(authEvent.permanentKey, equals(phase.config.permanentKey.publicKey));
    return phase;
  };
}

Phase? Function(Phase, Io) mkSendNoSharedTaskTest(PeerData initiator) {
  return (phase, io) {
    final closing = initiator.sendAndClose(
      message: Close(CloseCode.noSharedTask),
      sendTo: phase,
      encryptWith: crypto.createSharedKeyStore(
          ownKeyStore: initiator.testedPeer.ourSessionKey!,
          remotePublicKey: initiator.testedPeer.theirSessionKey!.publicKey),
    );

    expect(closing, isNull);

    io.expectEventOfType<events.NoSharedTaskFound>();
    return phase;
  };
}

Phase? Function(Phase, Io) mkInitiatorDisconnectedTest({
  required PeerData server,
}) {
  return (initialPhase, io) {
    final phase = server.sendAndTransitToPhase<ResponderClientHandshakePhase>(
      message: Disconnected(Id.initiatorAddress),
      sendTo: initialPhase,
      encryptWith: crypto.createSharedKeyStore(
          ownKeyStore: server.testedPeer.ourSessionKey!,
          remotePublicKey: server.testedPeer.permanentKey!.publicKey),
    );
    final disconnectedEvent = io.expectEventOfType<events.PeerDisconnected>();
    expect(disconnectedEvent.peerKind, events.PeerKind.unauthenticated);
    expect(phase.initiatorWithState, isNull);
    return phase;
  };
}

Phase? Function(Phase, Io) mkSendErrorTest({
  required PeerData server,
  required PeerData initiator,
}) {
  return (phaseUntyped, io) {
    final phase = server.sendAndTransitToPhase<ResponderClientHandshakePhase>(
      message: SendError(Uint8List.fromList([
        phaseUntyped.common.address.value,
        Id.initiatorAddress.value,
        0,
        0,
        1,
        2,
        3,
        4
      ])),
      sendTo: phaseUntyped,
      encryptWith: crypto.createSharedKeyStore(
          ownKeyStore: server.testedPeer.ourSessionKey!,
          remotePublicKey: server.testedPeer.permanentKey!.publicKey),
    );

    expect(phase.initiatorWithState, isNull);
    resetInitiatorData(initiator);

    final errEvent = io.expectEventOfType<events.SendingMessageToPeerFailed>();
    expect(errEvent.peerKind, events.PeerKind.unauthenticated);

    return phase;
  };
}

void resetInitiatorData(PeerData initiator) {
  final oldKnowledge = initiator.testedPeer;
  initiator.resetTestedClientKnowledge();
  initiator.testedPeer.permanentKey = oldKnowledge.permanentKey;
}
