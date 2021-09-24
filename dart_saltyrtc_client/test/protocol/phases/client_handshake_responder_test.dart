import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/src/crypto/crypto.dart'
    show AuthToken, Crypto;
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
import 'package:dart_saltyrtc_client/src/protocol/error.dart'
    show NoSharedTaskError;
import 'package:dart_saltyrtc_client/src/protocol/phases/client_handshake_responder.dart'
    show ResponderClientHandshakePhase, State;
import 'package:dart_saltyrtc_client/src/protocol/phases/phase.dart'
    show Common, CommonAfterServerHandshake, Phase, ResponderConfig;
import 'package:dart_saltyrtc_client/src/protocol/phases/task.dart'
    show ResponderTaskPhase;
import 'package:dart_saltyrtc_client/src/protocol/task.dart' show Task;
import 'package:test/test.dart';

import '../../crypto_mock.dart' show MockCrypto;
import '../../logging.dart' show setUpLogging;
import '../../network_mock.dart' show MockWebSocket, PackageQueue;
import '../../utils.dart'
    show PeerData, TestTask, phaseAs, runTest, throwsSaltyRtcError;

final crypto = MockCrypto();

void main() {
  setUpLogging();

  final crypto = MockCrypto();
  group('successful transition', () {
    test('key+token are send out on creation', () {
      final setup = _Setup.create(crypto: crypto);
      runTest(setup.initialPhase, [mkRecvTokenAndKeyTest(setup.initiator)]);
    });
    test('key is send out on creation', () {
      final setup = _Setup.create(crypto: crypto, usePresetTrust: true);
      runTest(setup.initialPhase, [mkRecvKeyTest(setup.initiator)]);
    });

    test('initiator connects later', () {
      final setup = _Setup.create(crypto: crypto, initiatorIsKnown: false);
      runTest(setup.initialPhase, [
        (phase, packages) {
          expect(packages, isEmpty);
          return phase;
        },
        mkNewInitiatorTest(initiator: setup.initiator, server: setup.server),
      ]);
    });

    test('initiator sends key', () {
      final tasks = [
        TestTask('bar foot'),
        TestTask('bar'),
        TestTask('example.v23')
      ];
      final setup =
          _Setup.create(crypto: crypto, usePresetTrust: true, tasks: tasks);
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
      final tasks = [TestTask('example.v23')];
      final setup =
          _Setup.create(crypto: crypto, usePresetTrust: true, tasks: tasks);
      final initiator = setup.initiator;
      runTest(setup.initialPhase, [
        mkRecvKeyTest(initiator),
        mkSendKeyRecvAuthTest(
          initiator: initiator,
          tasks: tasks,
        ),
        mkSendAuthTest(
            initiator: initiator,
            task: 'example.v23',
            data: {'example.v23': null}),
      ]);
    });
  });

  test('protocol error', () {
    final setup = _Setup.create(crypto: crypto);
    final initiator = setup.initiator;
    runTest(setup.initialPhase, [
      mkRecvTokenAndKeyTest(initiator),
      (phase, packages) {
        expect(() {
          initiator.sendAndTransitToPhase(
            message: Key(Uint8List(1)),
            sendTo: phase,
            encryptWith: crypto.createSharedKeyStore(
              ownKeyStore: initiator.permanentKey,
              remotePublicKey: initiator.testedPeer.permanentKey!.publicKey,
            ),
          );
        }, throwsSaltyRtcError(closeCode: CloseCode.protocolError));
        //TODO check that sink closed
        return phase;
      }
    ]);
  });

  test('auth -> no task found', () {
    final tasks = [TestTask('example.v23', null)];
    final setup =
        _Setup.create(crypto: crypto, usePresetTrust: true, tasks: tasks);
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
    final setup = _Setup.create(crypto: crypto, usePresetTrust: true);
    runTest(setup.initialPhase, [
      mkRecvKeyTest(setup.initiator),
      mkInitiatorDisconnectedTest(server: setup.server),
    ]);
  });

  test('initiator override', () {
    final setup = _Setup.create(crypto: crypto);
    runTest(setup.initialPhase, [
      mkRecvKeyTest(setup.initiator),
      mkNewInitiatorTest(initiator: setup.initiator, server: setup.server),
    ]);
  });
}

class _Setup {
  final Crypto crypto;
  final PeerData server;
  final PeerData initiator;
  final ResponderClientHandshakePhase initialPhase;

  _Setup({
    required this.crypto,
    required this.server,
    required this.initiator,
    required this.initialPhase,
  });

  factory _Setup.create({
    required Crypto crypto,
    bool usePresetTrust = false,
    bool badInitialAuth = false,
    bool initiatorIsKnown = true,
    List<Task>? tasks,
  }) {
    final responderId = Id.responderId(32);
    final responderPermanentKeys = crypto.createKeyStore();

    AuthToken? authToken;
    if (!usePresetTrust) {
      authToken = crypto.createAuthToken();
    }

    final initiator = PeerData(
      crypto: crypto,
      address: Id.initiatorAddress,
      testedPeerId: responderId,
      authToken: badInitialAuth ? crypto.createAuthToken() : authToken,
    );
    if (usePresetTrust) {
      initiator.testedPeer.permanentKey = responderPermanentKeys;
    }
    final server = PeerData(
      crypto: crypto,
      address: Id.serverAddress,
      testedPeerId: Id.initiatorAddress,
    );
    server.testedPeer.ourSessionKey = crypto.createKeyStore();
    server.testedPeer.theirSessionKey = crypto.createKeyStore();

    final common = Common(crypto, MockWebSocket());
    common.server.setSessionSharedKey(crypto.createSharedKeyStore(
      ownKeyStore: server.testedPeer.theirSessionKey!,
      remotePublicKey: server.testedPeer.ourSessionKey!.publicKey,
    ));
    common.address = responderId;

    final config = ResponderConfig(
      permanentKeys: responderPermanentKeys,
      tasks: tasks ?? [],
      initiatorPermanentPublicKey: initiator.permanentKey.publicKey,
      authToken: authToken,
      expectedServerPublicKey: server.permanentKey.publicKey,
    );

    final phase = ResponderClientHandshakePhase(
      CommonAfterServerHandshake(common),
      config,
      initiatorIsKnown,
    );

    return _Setup(
      crypto: crypto,
      server: server,
      initiator: initiator,
      initialPhase: phase,
    );
  }
}

Phase Function(Phase, PackageQueue) mkRecvTokenAndKeyTest(PeerData initiator) {
  final keyTest = mkRecvKeyTest(initiator);
  return (initialPhase, packages) {
    final phase = phaseAs<ResponderClientHandshakePhase>(initialPhase);

    final tokenMsg = initiator.expectMessageOfType<Token>(packages,
        decryptWith: initiator.authToken);

    expect(
        tokenMsg.key, equals(initialPhase.baseConfig.permanentKeys.publicKey));
    initiator.testedPeer.permanentKey = initialPhase.baseConfig.permanentKeys;

    return keyTest(phase, packages);
  };
}

Phase Function(Phase, PackageQueue) mkRecvKeyTest(PeerData initiator) {
  return (initialPhase, packages) {
    final keyMsg = initiator.expectMessageOfType<Key>(packages,
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

Phase Function(Phase, PackageQueue) mkNewInitiatorTest({
  required PeerData initiator,
  required PeerData server,
}) {
  final tokenAndKeyTest = mkRecvTokenAndKeyTest(initiator);
  return (initialPhase, packages) {
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

    return tokenAndKeyTest(phase, packages);
  };
}

Phase Function(Phase, PackageQueue) mkSendKeyRecvAuthTest({
  required PeerData initiator,
  required List<Task> tasks,
}) {
  return (initialPhase, packages) {
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

    final sessionSharedKey = crypto.createSharedKeyStore(
      ownKeyStore: phase.initiatorWithState!.sessionKey,
      remotePublicKey: sessionKey.publicKey,
    );
    expect(phase.initiatorWithState!.initiator.sessionSharedKey,
        same(sessionSharedKey));

    final authMsg = initiator.expectMessageOfType<AuthResponder>(packages,
        decryptWith: sessionSharedKey);

    expect(authMsg.yourCookie, equals(initiator.testedPeer.cookiePair.ours));
    final taskData = {for (final task in tasks) task.name: task.data};
    expect(authMsg.tasks, equals(taskData.keys));
    expect(authMsg.data, equals(taskData));
    return phase;
  };
}

//FIXME test: missing entry in data is error not nil
//FIXME check cookie is checked
Phase Function(Phase, PackageQueue) mkSendAuthTest({
  required PeerData initiator,
  required String task,
  required TasksData data,
}) {
  return (initialPhase, packages) {
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
    expect(taskObject.initWasCalled, isTrue);
    expect(taskObject.initData, equals(data));
    return phase;
  };
}

Phase Function(Phase, PackageQueue) mkSendNoSharedTaskTest(PeerData initiator) {
  return (initialPhase, packages) {
    expect(() {
      initiator.sendAndTransitToPhase<ResponderTaskPhase>(
        message: Close(CloseCode.noSharedTask),
        sendTo: initialPhase,
        encryptWith: crypto.createSharedKeyStore(
            ownKeyStore: initiator.testedPeer.ourSessionKey!,
            remotePublicKey: initiator.testedPeer.theirSessionKey!.publicKey),
      );
    }, throwsA(isA<NoSharedTaskError>()));
    //TODO check that sink was closed!
    return initialPhase;
  };
}

Phase Function(Phase, PackageQueue) mkInitiatorDisconnectedTest({
  required PeerData server,
}) {
  return (initialPhase, packages) {
    final phase = server.sendAndTransitToPhase<ResponderClientHandshakePhase>(
      message: Disconnected(Id.initiatorAddress),
      sendTo: initialPhase,
      encryptWith: crypto.createSharedKeyStore(
          ownKeyStore: server.testedPeer.ourSessionKey!,
          remotePublicKey: server.testedPeer.permanentKey!.publicKey),
    );

    expect(phase.initiatorWithState, isNull);
    return phase;
  };
}
