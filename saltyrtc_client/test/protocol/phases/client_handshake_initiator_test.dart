import 'dart:typed_data' show Uint8List;

import 'package:test/test.dart';
import 'package:xayn_saltyrtc_client/events.dart' as events;
import 'package:xayn_saltyrtc_client/src/crypto/crypto.dart'
    show InitialClientAuthMethod;
import 'package:xayn_saltyrtc_client/src/messages/c2c/auth_initiator.dart'
    show AuthInitiator;
import 'package:xayn_saltyrtc_client/src/messages/c2c/auth_responder.dart'
    show AuthResponder;
import 'package:xayn_saltyrtc_client/src/messages/c2c/close.dart' show Close;
import 'package:xayn_saltyrtc_client/src/messages/c2c/key.dart' show Key;
import 'package:xayn_saltyrtc_client/src/messages/c2c/token.dart' show Token;
import 'package:xayn_saltyrtc_client/src/messages/close_code.dart'
    show CloseCode, CloseCodeToFromInt;
import 'package:xayn_saltyrtc_client/src/messages/id.dart' show Id;
import 'package:xayn_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;
import 'package:xayn_saltyrtc_client/src/messages/s2c/disconnected.dart'
    show Disconnected;
import 'package:xayn_saltyrtc_client/src/messages/s2c/drop_responder.dart'
    show DropResponder;
import 'package:xayn_saltyrtc_client/src/messages/s2c/new_responder.dart'
    show NewResponder;
import 'package:xayn_saltyrtc_client/src/messages/s2c/send_error.dart'
    show SendError;
import 'package:xayn_saltyrtc_client/src/protocol/phases/client_handshake_initiator.dart'
    show InitiatorClientHandshakePhase, State;
import 'package:xayn_saltyrtc_client/src/protocol/phases/phase.dart'
    show InitiatorConfig, Phase;
import 'package:xayn_saltyrtc_client/src/protocol/phases/task.dart'
    show TaskPhase;

import '../../crypto_mock.dart' show crypto;
import '../../network_mock.dart' show EventQueue;
import '../../utils.dart'
    show
        Io,
        PeerData,
        TestTaskBuilder,
        createAfterServerHandshakeState,
        phaseAs,
        runTest,
        setUpTesting;

void main() {
  setUpTesting();

  group('successful transition', () {
    test('initial(expect token) -> key', () {
      final setup = _Setup.create();

      runTest(setup.initialPhase, [mkSendTokenTest(setup.responders[0])]);
    });

    test('initial(expect key) -> auth', () {
      final setup = _Setup.create(usePresetTrust: true);
      runTest(setup.initialPhase, [mkSendKeyTest(setup.responders.first)]);
    });

    test('key -> auth', () {
      final setup = _Setup.create();
      final mockPeer = setup.responders[0];
      runTest(setup.initialPhase, [
        mkSendTokenTest(mockPeer),
        mkSendKeyTest(mockPeer),
      ]);
    });

    test('auth -> next phase', () {
      final responderTasks = [
        TestTaskBuilder(
          'fe fe',
          initialResponderData: {
            'yo': [1, 4, 3]
          },
        ),
        TestTaskBuilder('example.v23', initialResponderData: {'xml': <int>[]}),
        TestTaskBuilder(
          'bar',
          initialResponderData: {
            'yes': [0, 0, 0]
          },
        ),
      ];
      final supportedTasks = [
        TestTaskBuilder('bar foot', initialResponderData: {'a': null}),
        TestTaskBuilder('bar', initialResponderData: {'b': null}),
        TestTaskBuilder('example.v23', initialResponderData: {'c': null}),
      ];
      final setup =
          _Setup.create(tasks: supportedTasks, responderIds: [2, 3, 4]);
      final mockPeer = setup.responders[0];
      runTest(setup.initialPhase, [
        mkSendTokenTest(mockPeer),
        mkSendKeyTest(mockPeer),
        mkSendAuthTest(
          responder: mockPeer,
          server: setup.server,
          supportedTasks: supportedTasks,
          responderTasks: responderTasks,
          matchingTask: 'example.v23',
        ),
      ]);
    });
  });

  group('auth/decryption failure', () {
    test('initial(expect token) -> drop', () {
      final setup =
          _Setup.create(responderIds: [12, 21, 111], goodResponderAt: 1);
      final server = setup.server;
      runTest(setup.initialPhase, [
        mkSendBadTokenTest(responder: setup.responders[0], server: server),
        mkSendTokenTest(setup.responders[1]),
        mkSendBadTokenTest(responder: setup.responders[2], server: server),
        (phaseUntyped, io) {
          final phase = phaseAs<InitiatorClientHandshakePhase>(phaseUntyped);
          expect(phase.responders.length, equals(1));
          expect(phase.responders, contains(setup.responders[1].address));
          return phase;
        }
      ]);
    });

    test('initial(expect key) -> drop', () {
      final setup = _Setup.create(
        responderIds: [12, 21, 111],
        goodResponderAt: 1,
        usePresetTrust: true,
      );
      final server = setup.server;
      runTest(setup.initialPhase, [
        mkSendBadKeyTest(responder: setup.responders[0], server: server),
        mkSendKeyTest(setup.responders[1]),
        mkSendBadKeyTest(responder: setup.responders[2], server: server),
        (phaseUntyped, io) {
          final phase = phaseAs<InitiatorClientHandshakePhase>(phaseUntyped);
          expect(phase.responders.length, equals(1));
          expect(phase.responders, contains(setup.responders[1].address));
          return phase;
        }
      ]);
    });

    test('key -> drop', () {
      final setup = _Setup.create();
      runTest(setup.initialPhase, [
        mkSendTokenTest(setup.responders.first),
        mkSendBadKeyTest(
          responder: setup.responders.first,
          server: setup.server,
        ),
        (phaseUntyped, io) {
          final phase = phaseAs<InitiatorClientHandshakePhase>(phaseUntyped);
          expect(phase.responders, isEmpty);
          return phase;
        }
      ]);
    });

    test('auth -> protocol error', () {
      final setup = _Setup.create();
      final responder = setup.responders.first;
      final server = setup.server;
      runTest(setup.initialPhase, [
        mkSendTokenTest(responder),
        mkSendKeyTest(responder),
        (initialPhase, io) {
          final phase =
              responder.sendAndTransitToPhase<InitiatorClientHandshakePhase>(
            message: Close(CloseCode.goingAway),
            sendTo: initialPhase,
            encryptWith: crypto.createSharedKeyStore(
              ownKeyStore: responder.testedPeer.ourSessionKey!,
              remotePublicKey: responder.testedPeer.theirSessionKey!.publicKey,
            ),
          );

          final dropMsg = io.expectMessageOfType<DropResponder>(
            sendTo: server,
            decryptWith: crypto.createSharedKeyStore(
              ownKeyStore: server.testedPeer.ourSessionKey!,
              remotePublicKey: server.testedPeer.permanentKey!.publicKey,
            ),
          );
          final pev = io.expectEventOfType<events.ProtocolErrorWithPeer>();
          expect(pev.peerKind, events.PeerKind.unauthenticated);

          expect(dropMsg.id, equals(responder.address));
          return phase;
        }
      ]);
    });

    test('auth your_cookie is checked', () {
      final responderTasks = [
        TestTaskBuilder(
          'fe fe',
          initialResponderData: {
            'yo': [1, 4, 3]
          },
        ),
        TestTaskBuilder('example.v23', initialResponderData: {'xml': <int>[]}),
        TestTaskBuilder(
          'bar',
          initialResponderData: {
            'yes': [0, 0, 0]
          },
        ),
      ];
      final supportedTasks = [
        TestTaskBuilder('bar foot', initialResponderData: {'a': null}),
        TestTaskBuilder('bar', initialResponderData: {'b': null}),
        TestTaskBuilder('example.v23', initialResponderData: {'c': null}),
      ];
      final setup =
          _Setup.create(tasks: supportedTasks, responderIds: [2, 3, 4]);
      final server = setup.server;
      final responder = setup.responders[0];
      runTest(setup.initialPhase, [
        mkSendTokenTest(responder),
        mkSendKeyTest(responder),
        (initialPhase, io) {
          final tasksData = {
            for (final task in responderTasks)
              task.name: task.getInitialResponderData()
          };

          final phase =
              responder.sendAndTransitToPhase<InitiatorClientHandshakePhase>(
            message: AuthResponder(
              responder.testedPeer.cookiePair.ours,
              tasksData.keys.toList(),
              tasksData,
            ),
            sendTo: initialPhase,
            encryptWith: crypto.createSharedKeyStore(
              ownKeyStore: responder.testedPeer.ourSessionKey!,
              remotePublicKey: responder.testedPeer.theirSessionKey!.publicKey,
            ),
          );

          expect(phase.responders[responder.address], isNull);
          final event = io.expectEventOfType<events.ProtocolErrorWithPeer>();
          expect(event.peerKind, events.PeerKind.unauthenticated);

          final dropMsg = io.expectMessageOfType<DropResponder>(
            sendTo: server,
            decryptWith: crypto.createSharedKeyStore(
              ownKeyStore: server.testedPeer.permanentKey!,
              remotePublicKey: server.testedPeer.ourSessionKey!.publicKey,
            ),
          );

          expect(dropMsg.id, equals(responder.address));
          return phase;
        }
      ]);
    });

    group('send-error checks', () {
      test('send-error source is checked', () {
        final setup = _Setup.create(
          usePresetTrust: true,
        );
        final server = setup.server;
        final responder0 = setup.responders[0];

        runTest(setup.initialPhase, [
          mkSendKeyTest(responder0),
          mkSendBadSendErrorTest(
            server: server,
            source: Id.peerId(32),
            destination: responder0.address,
          ),
        ]);
      });

      test('send-error destination is checked', () {
        final setup = _Setup.create(usePresetTrust: true);
        final server = setup.server;
        final responder0 = setup.responders[0];

        runTest(setup.initialPhase, [
          mkSendKeyTest(responder0),
          mkSendBadSendErrorTest(
            server: server,
            source: Id.initiatorAddress,
            destination: Id.initiatorAddress,
          ),
        ]);
      });
    });
  });

  test('auth -> no task found', () {
    final responderTasks = [
      TestTaskBuilder(
        'fe fe',
        initialResponderData: {
          'yo': [1, 4, 3],
        },
      ),
      TestTaskBuilder('example.v23', initialResponderData: {'xml': <int>[]}),
      TestTaskBuilder(
        'bar',
        initialResponderData: {
          'yes': [0, 0, 0]
        },
      ),
    ];
    final supportedTasks = [
      TestTaskBuilder('bar foot'),
      TestTaskBuilder('bor'),
      TestTaskBuilder('duck')
    ];
    final setup = _Setup.create(tasks: supportedTasks, responderIds: [2, 3, 4]);
    final responder = setup.responders[0];
    runTest(setup.initialPhase, [
      mkSendTokenTest(responder),
      mkSendKeyTest(responder),
      mkSendAuthNoSharedTaskTest(
        responder: responder,
        supportedTasks: supportedTasks,
        responderTasks: responderTasks,
      )
    ]);
  });

  test('path cleaning is done', () {
    final setup = _Setup.create(
      responderIds: List.generate(252, (index) => index + 2),
      goodResponderAt: 1,
    );
    final server = setup.server;
    runTest(setup.initialPhase, [
      mkSendTokenTest(setup.responders[1]),
      mkDropOldOnNewReceiverTest(
        newResponderId: 255,
        droppedResponderId: 2,
        server: server,
      ),
      mkDropOldOnNewReceiverTest(
        newResponderId: 2,
        droppedResponderId: 4,
        server: server,
      ),
      mkDropOldOnNewReceiverTest(
        newResponderId: 4,
        droppedResponderId: 5,
        server: server,
      ),
    ]);
  });

  test('handleDisconnected', () {
    final setup = _Setup.create(
      responderIds: [20, 30, 40, 50],
      goodResponderAt: 1,
    );
    final server = setup.server;
    runTest(setup.initialPhase, [
      mkSendTokenTest(setup.responders[1]),
      mkSendDisconnectedTest(
        server: server,
        disconnect: 50,
      ),
      mkSendDisconnectedTest(
        server: server,
        disconnect: 30,
        doesMatter: true,
      ),
      mkSendDisconnectedTest(
        server: server,
        disconnect: 20,
        doesMatter: true,
      ),
    ]);
  });

  test('handle SendError', () {
    final setup = _Setup.create(
      responderIds: [20, 30, 40],
      goodResponderAt: 1,
    );
    final server = setup.server;

    runTest(setup.initialPhase, [
      mkSendErrorTest(server: server, responder: setup.responders[0]),
      mkSendTokenTest(setup.responders[1]),
      mkSendErrorTest(server: server, responder: setup.responders[1]),
      mkSendErrorTest(server: server, responder: setup.responders[2]),
    ]);
  });
}

class _Setup {
  final PeerData server;
  final List<PeerData> responders;
  final InitiatorClientHandshakePhase initialPhase;
  final EventQueue events;

  _Setup._(
    this.server,
    this.responders,
    this.initialPhase,
    this.events,
  );

  factory _Setup.create({
    int goodResponderAt = 0,
    bool usePresetTrust = false,
    List<int>? responderIds,
    List<TestTaskBuilder>? tasks,
  }) {
    responderIds ??= [12];
    final goodResponder = responderIds[goodResponderAt];
    final badAuthToken = usePresetTrust ? null : crypto.createAuthToken();
    final goodAuthToken = usePresetTrust ? null : crypto.createAuthToken();

    final responders = responderIds
        .map(
          (address) => PeerData(
            address: Id.responderId(address),
            testedPeerId: Id.initiatorAddress,
            authToken: address == goodResponder ? goodAuthToken : badAuthToken,
          ),
        )
        .toList(growable: false);

    final sAndC = createAfterServerHandshakeState(Id.initiatorAddress);
    final server = sAndC.first;
    final common = sAndC.second;
    final initiatorPermanentKeys = server.testedPeer.permanentKey!;

    final authMethod = InitialClientAuthMethod.fromEither(
      authToken: usePresetTrust ? null : goodAuthToken,
      trustedResponderPermanentPublicKey: usePresetTrust
          ? responders[goodResponderAt].permanentKey.publicKey
          : null,
      crypto: crypto,
      initiatorPermanentKeys: initiatorPermanentKeys,
    );

    final config = InitiatorConfig(
      authMethod: authMethod,
      permanentKeys: initiatorPermanentKeys,
      tasks: tasks ?? [],
      expectedServerPublicKey: server.permanentKey.publicKey,
    );

    final phase = InitiatorClientHandshakePhase(common, config);

    server.testedPeer.permanentKey = phase.config.permanentKey;
    for (final responder in responders) {
      // we know the initiators public key as it's in the path
      responder.testedPeer.permanentKey = phase.config.permanentKey;
      phase.addNewResponder(responder.address.asResponder());
    }

    return _Setup._(server, responders, phase, common.events as EventQueue);
  }
}

Phase? Function(Phase, Io) mkSendTokenTest(PeerData mockPeer) {
  assert(mockPeer.authToken != null);
  return (initialPhase, io) {
    final phase = mockPeer.sendAndTransitToPhase<InitiatorClientHandshakePhase>(
      message: Token(mockPeer.permanentKey.publicKey),
      sendTo: initialPhase,
      encryptWith: mockPeer.authToken!,
    );
    final responderData = phase.responders[mockPeer.address]!;
    final responder = responderData.responder;
    expect(responderData.state, equals(State.waitForKeyMsg));
    expect(responder.id, equals(mockPeer.address));
    expect(responder.hasSessionSharedKey, isFalse);
    expect(responder.hasPermanentSharedKey, isTrue);
    final expectedKey = crypto.createSharedKeyStore(
      ownKeyStore: phase.config.permanentKey,
      remotePublicKey: mockPeer.permanentKey.publicKey,
    );
    expect(responder.permanentSharedKey, same(expectedKey));
    return phase;
  };
}

Phase? Function(Phase, Io) mkSendBadTokenTest({
  required PeerData responder,
  required PeerData server,
}) {
  assert(responder.authToken != null);
  return (initialPhase, io) {
    var phase = phaseAs<InitiatorClientHandshakePhase>(initialPhase);
    phase = responder.sendAndTransitToPhase<InitiatorClientHandshakePhase>(
      message: Token(responder.permanentKey.publicKey),
      sendTo: initialPhase,
      encryptWith: responder.authToken,
    );
    expect(phase.responders.containsKey(responder.address), isFalse);
    final dropMsg = io.expectMessageOfType<DropResponder>(
      sendTo: server,
      decryptWith: crypto.createSharedKeyStore(
        ownKeyStore: server.testedPeer.permanentKey!,
        remotePublicKey: server.testedPeer.ourSessionKey!.publicKey,
      ),
    );
    expect(dropMsg.id, equals(responder.address));
    expect(dropMsg.reason, equals(CloseCode.initiatorCouldNotDecrypt));
    io.expectEventOfType<events.InitiatorCouldNotDecrypt>();
    return phase;
  };
}

Phase? Function(Phase, Io) mkSendKeyTest(PeerData responder) {
  return (initialPhase, io) {
    responder.testedPeer.ourSessionKey = crypto.createKeyStore();
    final sendPubKey = responder.testedPeer.ourSessionKey!.publicKey;
    final phase =
        responder.sendAndTransitToPhase<InitiatorClientHandshakePhase>(
      message: Key(sendPubKey),
      sendTo: initialPhase,
      encryptWith: crypto.createSharedKeyStore(
        ownKeyStore: responder.permanentKey,
        remotePublicKey: responder.testedPeer.permanentKey!.publicKey,
      ),
    );
    final responderData = phase.responders[responder.address]!;
    final responderFromPhase = responderData.responder;
    expect(responderData.state, equals(State.waitForAuth));
    expect(responderFromPhase.id, equals(responder.address));
    expect(responderFromPhase.hasPermanentSharedKey, isTrue);
    final expectedSharedPermanentKey = crypto.createSharedKeyStore(
      ownKeyStore: phase.config.permanentKey,
      remotePublicKey: responder.permanentKey.publicKey,
    );
    expect(
      responderFromPhase.permanentSharedKey,
      same(expectedSharedPermanentKey),
    );
    expect(responderFromPhase.hasSessionSharedKey, isTrue);
    final decryptWith = crypto.createSharedKeyStore(
      ownKeyStore: responder.permanentKey,
      remotePublicKey: responder.testedPeer.permanentKey!.publicKey,
    );
    final msg = io.expectMessageOfType<Key>(
      sendTo: responder,
      decryptWith: decryptWith,
    );
    final initiatorSessionKey = crypto.getKeyStoreForKey(msg.key)!;
    final expectedSharedSessionKey = crypto.createSharedKeyStore(
      ownKeyStore: initiatorSessionKey,
      remotePublicKey: sendPubKey,
    );
    expect(responderFromPhase.sessionSharedKey, same(expectedSharedSessionKey));
    responder.testedPeer.theirSessionKey = initiatorSessionKey;
    return phase;
  };
}

Phase? Function(Phase, Io) mkSendBadKeyTest({
  required PeerData responder,
  required PeerData server,
}) {
  return (initialPhase, io) {
    responder.testedPeer.ourSessionKey = crypto.createKeyStore();
    final sendPubKey = responder.testedPeer.ourSessionKey!.publicKey;
    final phase =
        responder.sendAndTransitToPhase<InitiatorClientHandshakePhase>(
      message: Key(sendPubKey),
      sendTo: initialPhase,
      encryptWith: crypto.createSharedKeyStore(
        ownKeyStore: responder.permanentKey,
        remotePublicKey: responder.testedPeer.permanentKey!.publicKey,
      ),
      mapEncryptedMessage: (msg) {
        msg.setAll(
          Nonce.totalLength,
          Uint8List(msg.length - Nonce.totalLength),
        );
        return msg;
      },
    );
    expect(phase.responders.containsKey(responder.address), isFalse);
    final dropMsg = io.expectMessageOfType<DropResponder>(
      sendTo: server,
      decryptWith: crypto.createSharedKeyStore(
        ownKeyStore: server.testedPeer.permanentKey!,
        remotePublicKey: server.testedPeer.ourSessionKey!.publicKey,
      ),
    );
    expect(dropMsg.id, equals(responder.address));
    expect(dropMsg.reason, equals(CloseCode.initiatorCouldNotDecrypt));
    io.expectEventOfType<events.InitiatorCouldNotDecrypt>();
    return phase;
  };
}

Phase? Function(Phase, Io) mkSendAuthNoSharedTaskTest({
  required PeerData responder,
  required List<TestTaskBuilder> supportedTasks,
  required List<TestTaskBuilder> responderTasks,
}) {
  return (phase, io) {
    final tasksData = {
      for (final task in responderTasks)
        task.name: task.getInitialResponderData()
    };

    final closing = responder.sendAndClose(
      message: AuthResponder(
        responder.testedPeer.cookiePair.theirs!,
        tasksData.keys.toList(),
        tasksData,
      ),
      sendTo: phase,
      encryptWith: crypto.createSharedKeyStore(
        ownKeyStore: responder.testedPeer.ourSessionKey!,
        remotePublicKey: responder.testedPeer.theirSessionKey!.publicKey,
      ),
    );

    expect(closing, equals(CloseCode.goingAway.toInt()));

    io.expectEventOfType<events.NoSharedTaskFound>();

    for (final task in supportedTasks) {
      expect(task.lastInitiatorTask, isNull);
      expect(task.lastResponderTask, isNull);
    }

    final msg = io.expectMessageOfType<Close>(
      sendTo: responder,
      decryptWith: crypto.createSharedKeyStore(
        ownKeyStore: responder.testedPeer.ourSessionKey!,
        remotePublicKey: responder.testedPeer.theirSessionKey!.publicKey,
      ),
    );

    expect(msg.reason, CloseCode.noSharedTask);

    return null;
  };
}

Phase? Function(Phase, Io) mkSendAuthTest({
  required PeerData responder,
  required PeerData server,
  required List<TestTaskBuilder> supportedTasks,
  required List<TestTaskBuilder> responderTasks,
  required String matchingTask,
}) {
  return (initialPhase, io) {
    final tasksData = {
      for (final task in responderTasks)
        task.name: task.getInitialResponderData()
    };
    final phase = responder.sendAndTransitToPhase<TaskPhase>(
      message: AuthResponder(
        responder.testedPeer.cookiePair.theirs!,
        tasksData.keys.toList(),
        tasksData,
      ),
      sendTo: initialPhase,
      encryptWith: crypto.createSharedKeyStore(
        ownKeyStore: responder.testedPeer.ourSessionKey!,
        remotePublicKey: responder.testedPeer.theirSessionKey!.publicKey,
      ),
    );

    for (final task in supportedTasks) {
      if (task.name == matchingTask) {
        expect(task.lastInitiatorTask, isNotNull);
        expect(task.lastResponderTask, isNull);
        final data = tasksData[matchingTask]!;
        // when passing though the initiator creation we add a field
        data['initWasCalled'] = [1, 0, 12];
        expect(
          task.lastInitiatorTask!.initData,
          equals(tasksData[matchingTask]),
        );
      } else {
        expect(task.lastInitiatorTask, isNull);
        expect(task.lastResponderTask, isNull);
      }
    }

    final authMsg = io.expectMessageOfType<AuthInitiator>(
      sendTo: responder,
      decryptWith: crypto.createSharedKeyStore(
        ownKeyStore: responder.testedPeer.ourSessionKey!,
        remotePublicKey: responder.testedPeer.theirSessionKey!.publicKey,
      ),
    );

    expect(authMsg.yourCookie, responder.testedPeer.cookiePair.ours);
    expect(authMsg.task, matchingTask);
    expect(
      authMsg.data,
      equals({
        matchingTask: supportedTasks
            .firstWhere((task) => task.name == matchingTask)
            .buildInitiatorTask(tasksData[matchingTask])
            .second
      }),
    );

    var dropMsg = io.expectMessageOfType<DropResponder>(
      sendTo: server,
      decryptWith: crypto.createSharedKeyStore(
        ownKeyStore: server.testedPeer.ourSessionKey!,
        remotePublicKey: server.testedPeer.permanentKey!.publicKey,
      ),
    );
    expect(dropMsg.id, equals(Id.responderId(3)));
    expect(dropMsg.reason, equals(CloseCode.droppedByInitiator));

    dropMsg = io.expectMessageOfType<DropResponder>(
      sendTo: server,
      decryptWith: crypto.createSharedKeyStore(
        ownKeyStore: server.testedPeer.ourSessionKey!,
        remotePublicKey: server.testedPeer.permanentKey!.publicKey,
      ),
    );
    expect(dropMsg.id, equals(Id.responderId(4)));
    expect(dropMsg.reason, equals(CloseCode.droppedByInitiator));

    final authEvent = io.expectEventOfType<events.ResponderAuthenticated>();
    expect(authEvent.permanentKey, equals(responder.permanentKey.publicKey));

    return phase;
  };
}

Phase? Function(Phase, Io) mkDropOldOnNewReceiverTest({
  required int newResponderId,
  required int droppedResponderId,
  required PeerData server,
}) {
  return (initialPhase, io) {
    final nrOfResponders =
        phaseAs<InitiatorClientHandshakePhase>(initialPhase).responders.length;
    expect(nrOfResponders, equals(252));
    final newId = Id.responderId(newResponderId);
    final droppedId = Id.responderId(droppedResponderId);
    final phase = server.sendAndTransitToPhase<InitiatorClientHandshakePhase>(
      message: NewResponder(newId),
      sendTo: initialPhase,
      encryptWith: crypto.createSharedKeyStore(
        ownKeyStore: server.testedPeer.ourSessionKey!,
        remotePublicKey: server.testedPeer.permanentKey!.publicKey,
      ),
    );

    final dropMsg = io.expectMessageOfType<DropResponder>(
      sendTo: server,
      decryptWith: crypto.createSharedKeyStore(
        ownKeyStore: server.testedPeer.ourSessionKey!,
        remotePublicKey: server.testedPeer.permanentKey!.publicKey,
      ),
    );

    expect(dropMsg.id, equals(droppedId));
    expect(phase.responders.keys, contains(newId));
    expect(phase.responders[droppedId], isNull);
    expect(phase.responders.length, equals(252));
    return phase;
  };
}

Phase? Function(Phase, Io) mkSendDisconnectedTest({
  required int disconnect,
  required PeerData server,
  bool doesMatter = false,
}) {
  final disconnectId = Id.responderId(disconnect);
  return (initialPhaseUntyped, io) {
    final initialPhase =
        phaseAs<InitiatorClientHandshakePhase>(initialPhaseUntyped);
    final otherResponders = initialPhase.responders.keys
        .where((id) => id.value != disconnect)
        .toList();
    final phase = server.sendAndTransitToPhase<InitiatorClientHandshakePhase>(
      message: Disconnected(disconnectId),
      sendTo: initialPhase,
      encryptWith: crypto.createSharedKeyStore(
        ownKeyStore: server.testedPeer.ourSessionKey!,
        remotePublicKey: server.testedPeer.permanentKey!.publicKey,
      ),
    );
    expect(phase.responders.keys, equals(otherResponders));
    expect(phase.responders[disconnect], isNull);
    if (doesMatter) {
      final disconnectedMsg = io.expectEventOfType<events.PeerDisconnected>();
      expect(disconnectedMsg.peerKind, events.PeerKind.unauthenticated);
    } else {
      final disconnectedMsg =
          io.expectEventOfType<events.AdditionalResponderEvent>();
      expect(disconnectedMsg.event, isA<events.PeerDisconnected>());

      expect(
        (disconnectedMsg.event as events.PeerDisconnected).peerKind,
        events.PeerKind.unauthenticated,
      );
    }
    return phase;
  };
}

Phase? Function(Phase, Io) mkSendErrorTest({
  required PeerData server,
  required PeerData responder,
}) {
  return (initialPhaseUntyped, io) {
    var phase = phaseAs<InitiatorClientHandshakePhase>(initialPhaseUntyped);
    final otherResponders =
        phase.responders.keys.where((id) => id != responder.address).toList();

    phase = server.sendAndTransitToPhase<InitiatorClientHandshakePhase>(
      message: SendError(
        Uint8List.fromList([
          phase.common.address.value,
          responder.address.value,
          0,
          0,
          1,
          2,
          3,
          4
        ]),
      ),
      sendTo: initialPhaseUntyped,
      encryptWith: crypto.createSharedKeyStore(
        ownKeyStore: server.testedPeer.ourSessionKey!,
        remotePublicKey: server.testedPeer.permanentKey!.publicKey,
      ),
    );
    expect(phase.responders.keys, equals(otherResponders));
    expect(phase.responders[responder.address], isNull);

    final errEvent = io.expectEventOfType<events.SendingMessageToPeerFailed>();
    expect(errEvent.peerKind, events.PeerKind.unauthenticated);
    return phase;
  };
}

Phase? Function(Phase, Io) mkSendBadSendErrorTest({
  required PeerData server,
  required Id source,
  required Id destination,
}) {
  return (initialPhase, io) {
    final closing = server.sendAndClose(
      message: SendError(
        Uint8List.fromList([source.value, destination.value, 0, 0, 1, 2, 3, 4]),
      ),
      sendTo: initialPhase,
      encryptWith: crypto.createSharedKeyStore(
        ownKeyStore: server.testedPeer.ourSessionKey!,
        remotePublicKey: server.testedPeer.permanentKey!.publicKey,
      ),
    );
    expect(closing, equals(CloseCode.protocolError.toInt()));

    io.expectEventOfType<events.ProtocolErrorWithServer>();
    return null;
  };
}
