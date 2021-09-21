import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/src/crypto/crypto.dart'
    show Crypto, InitialClientAuthMethod;
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
import 'package:dart_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;
import 'package:dart_saltyrtc_client/src/messages/s2c/drop_responder.dart'
    show DropResponder;
import 'package:dart_saltyrtc_client/src/messages/s2c/new_responder.dart'
    show NewResponder;
import 'package:dart_saltyrtc_client/src/protocol/error.dart'
    show IgnoreMessageError, NoSharedTaskError, ProtocolError;
import 'package:dart_saltyrtc_client/src/protocol/phases/client_handshake_initiator.dart'
    show InitiatorClientHandshakePhase, State;
import 'package:dart_saltyrtc_client/src/protocol/phases/phase.dart'
    show ClientHandshakeInput, Common, CommonAfterServerHandshake, Phase;
import 'package:dart_saltyrtc_client/src/protocol/phases/task.dart'
    show TaskPhase;
import 'package:dart_saltyrtc_client/src/protocol/task.dart' show Task;
import 'package:test/test.dart';

import '../../crypto_mock.dart' show MockCrypto;
import '../../logging.dart' show setUpLogging;
import '../../network_mock.dart' show MockWebSocket2, PackageQueue;
import '../../utils.dart' show PeerData, TestTask, phaseAs, runTest;

void main() {
  setUpLogging();

  final crypto = MockCrypto();
  group('successful transition', () {
    test('initial(expect token) -> key', () {
      final setup = _Setup.create(crypto: crypto);

      runTest(
          setup.initialPhase, [mkSendTokenTest(crypto, setup.responders[0])]);
    });

    test('initial(expect key) -> auth', () {
      final setup = _Setup.create(crypto: crypto, usePresetTrust: true);
      runTest(
          setup.initialPhase, [mkSendKeyTest(crypto, setup.responders.first)]);
    });

    test('key -> auth', () {
      final setup = _Setup.create(crypto: crypto);
      final mockPeer = setup.responders[0];
      runTest(setup.initialPhase, [
        mkSendTokenTest(crypto, mockPeer),
        mkSendKeyTest(crypto, mockPeer),
      ]);
    });

    test('auth -> next phase', () {
      final tasks = [
        TestTask('bar foot'),
        TestTask('bar'),
        TestTask('example.v23')
      ];
      final setup =
          _Setup.create(crypto: crypto, tasks: tasks, responderIds: [2, 3, 4]);
      final mockPeer = setup.responders[0];
      runTest(setup.initialPhase, [
        mkSendTokenTest(crypto, mockPeer),
        mkSendKeyTest(crypto, mockPeer),
        mkSendAuthTest(crypto,
            responder: mockPeer, server: setup.server, tasks: tasks),
      ]);
    });
  });

  group('auth/decryption failure', () {
    test('initial(expect token) -> drop', () {
      final setup = _Setup.create(
          crypto: crypto, responderIds: [12, 21, 111], goodResponderAt: 1);
      final server = setup.server;
      runTest(setup.initialPhase, [
        mkSendBadTokenTest(crypto,
            responder: setup.responders[0], server: server),
        mkSendTokenTest(crypto, setup.responders[1]),
        mkSendBadTokenTest(crypto,
            responder: setup.responders[2], server: server),
        (phaseUntyped, packages) {
          final phase = phaseAs<InitiatorClientHandshakePhase>(phaseUntyped);
          expect(phase.responders.length, equals(1));
          expect(phase.responders, contains(setup.responders[1].address));
          return phase;
        }
      ]);
    });

    test('initial(expect key) -> drop', () {
      final setup = _Setup.create(
          crypto: crypto,
          responderIds: [12, 21, 111],
          goodResponderAt: 1,
          usePresetTrust: true);
      final server = setup.server;
      runTest(setup.initialPhase, [
        mkSendBadKeyTest(crypto,
            responder: setup.responders[0], server: server),
        mkSendKeyTest(crypto, setup.responders[1]),
        mkSendBadKeyTest(crypto,
            responder: setup.responders[2], server: server),
        (phaseUntyped, packages) {
          final phase = phaseAs<InitiatorClientHandshakePhase>(phaseUntyped);
          expect(phase.responders.length, equals(1));
          expect(phase.responders, contains(setup.responders[1].address));
          return phase;
        }
      ]);
    });

    test('key -> drop', () {
      final setup = _Setup.create(crypto: crypto);
      runTest(setup.initialPhase, [
        mkSendTokenTest(crypto, setup.responders.first),
        mkSendBadKeyTest(crypto,
            responder: setup.responders.first, server: setup.server),
        (phaseUntyped, packages) {
          final phase = phaseAs<InitiatorClientHandshakePhase>(phaseUntyped);
          expect(phase.responders, isEmpty);
          return phase;
        }
      ]);
    });

    test('auth -> protocol error', () {
      final setup = _Setup.create(crypto: crypto);
      final mockPeer = setup.responders.first;
      runTest(setup.initialPhase, [
        mkSendTokenTest(crypto, mockPeer),
        mkSendKeyTest(crypto, mockPeer),
        (initialPhase, packages) {
          try {
            mockPeer.sendAndTransitToPhase<TaskPhase>(
                message: Close(CloseCode.goingAway),
                to: initialPhase,
                encryptWith: crypto.createSharedKeyStore(
                    ownKeyStore: mockPeer.testedPeer.ourSessionKey!,
                    remotePublicKey:
                        mockPeer.testedPeer.theirSessionKey!.publicKey));
          } on ProtocolError {
            //TODO[later PR] make sure we got dropped
            return initialPhase;
          }
          throw AssertionError('expected sending wrong message to fail');
        }
      ]);
    });
  });

  test('auth -> no task found', () {
    final tasks = [
      TestTask('bar foot'),
      TestTask('bar'),
      TestTask('example.v23')
    ];
    final setup =
        _Setup.create(crypto: crypto, tasks: tasks, responderIds: [2, 3, 4]);
    final mockPeer = setup.responders[0];
    runTest(setup.initialPhase, [
      mkSendTokenTest(crypto, mockPeer),
      mkSendKeyTest(crypto, mockPeer),
      mkSendAuthTest(crypto,
          responder: mockPeer, server: setup.server, tasks: tasks),
    ]);
  });

  test('path cleaning is done', () {
    final setup = _Setup.create(
      crypto: crypto,
      responderIds: List.generate(252, (index) => index + 2),
      goodResponderAt: 1,
    );
    final server = setup.server;
    runTest(setup.initialPhase, [
      mkSendTokenTest(crypto, setup.responders[1]),
      mkDropOldOnNewReceiverTest(
        newResponderId: 255,
        droppedResponderId: 2,
        crypto: crypto,
        server: server,
      ),
      mkDropOldOnNewReceiverTest(
        newResponderId: 2,
        droppedResponderId: 4,
        crypto: crypto,
        server: server,
      ),
      mkDropOldOnNewReceiverTest(
        newResponderId: 4,
        droppedResponderId: 5,
        crypto: crypto,
        server: server,
      ),
    ]);
  });
}

class _Setup {
  final Crypto crypto;
  final PeerData server;
  final List<PeerData> responders;
  final InitiatorClientHandshakePhase initialPhase;

  _Setup({
    required this.crypto,
    required this.server,
    required this.responders,
    required this.initialPhase,
  });

  factory _Setup.create({
    required Crypto crypto,
    int goodResponderAt = 0,
    bool usePresetTrust = false,
    List<int>? responderIds,
    List<Task>? tasks,
  }) {
    responderIds ??= [12];
    final goodResponder = responderIds[goodResponderAt];
    final badAuthToken = usePresetTrust ? null : crypto.createAuthToken();
    final goodAuthToken = usePresetTrust ? null : crypto.createAuthToken();

    final responders = responderIds
        .map((address) => PeerData(
            crypto: crypto,
            address: Id.responderId(address),
            testedPeerId: Id.initiatorAddress,
            authToken: address == goodResponder ? goodAuthToken : badAuthToken))
        .toList(growable: false);

    final server = PeerData(
      crypto: crypto,
      address: Id.serverAddress,
      testedPeerId: Id.initiatorAddress,
    );
    final common = Common(crypto, crypto.createKeyStore(),
        server.permanentKey.publicKey, MockWebSocket2());
    server.testedPeer.ourSessionKey = crypto.createKeyStore();
    server.testedPeer.theirSessionKey = crypto.createKeyStore();
    common.server.setSessionSharedKey(crypto.createSharedKeyStore(
      ownKeyStore: server.testedPeer.theirSessionKey!,
      remotePublicKey: server.testedPeer.ourSessionKey!.publicKey,
    ));
    common.address = Id.initiatorAddress;

    final authMethod = InitialClientAuthMethod.fromEither(
        authToken: usePresetTrust ? null : goodAuthToken,
        trustedResponderPermanentPublicKey: usePresetTrust
            ? responders[goodResponderAt].permanentKey.publicKey
            : null,
        crypto: crypto,
        initiatorPermanentKeys: common.ourKeys);

    final phase = InitiatorClientHandshakePhase(
        CommonAfterServerHandshake(common),
        ClientHandshakeInput(tasks: tasks ?? [], authMethod: authMethod));

    for (final responder in responders) {
      // we know the initiators public key as it's in the path
      responder.testedPeer.permanentKey = phase.common.ourKeys;
      phase.addNewResponder(responder.address.asResponder());
    }

    return _Setup(
      crypto: crypto,
      server: server,
      responders: responders,
      initialPhase: phase,
    );
  }
}

Phase Function(Phase, PackageQueue) mkSendTokenTest(
    Crypto crypto, PeerData mockPeer) {
  assert(mockPeer.authToken != null);
  return (initialPhase, packages) {
    final phase = mockPeer.sendAndTransitToPhase<InitiatorClientHandshakePhase>(
      message: Token(mockPeer.permanentKey.publicKey),
      to: initialPhase,
      encryptWith: mockPeer.authToken!,
    );
    final responderData = phase.responders[mockPeer.address]!;
    final responder = responderData.responder;
    expect(responderData.state, equals(State.waitForKeyMsg));
    expect(responder.id, equals(mockPeer.address));
    expect(responder.hasSessionSharedKey, isFalse);
    expect(responder.hasPermanentSharedKey, isTrue);
    final expectedKey = crypto.createSharedKeyStore(
        ownKeyStore: phase.common.ourKeys,
        remotePublicKey: mockPeer.permanentKey.publicKey);
    expect(responder.permanentSharedKey, same(expectedKey));
    return phase;
  };
}

Phase Function(Phase, PackageQueue) mkSendBadTokenTest(Crypto crypto,
    {required PeerData responder, required PeerData server}) {
  assert(responder.authToken != null);
  return (initialPhase, packages) {
    var phase = phaseAs<InitiatorClientHandshakePhase>(initialPhase);
    try {
      phase = responder.sendAndTransitToPhase<InitiatorClientHandshakePhase>(
        message: Token(responder.permanentKey.publicKey),
        to: initialPhase,
        encryptWith: responder.authToken,
      );
      // ignore: empty_catches
    } on IgnoreMessageError {}
    expect(phase.responders.containsKey(responder.address), isFalse);
    final dropMsg = server.expectMessageOfType<DropResponder>(packages,
        decryptWith: crypto.createSharedKeyStore(
            ownKeyStore: server.testedPeer.theirSessionKey!,
            remotePublicKey: server.testedPeer.ourSessionKey!.publicKey));
    expect(dropMsg.id, equals(responder.address));
    expect(dropMsg.reason, equals(CloseCode.initiatorCouldNotDecrypt));
    return phase;
  };
}

Phase Function(Phase, PackageQueue) mkSendKeyTest(
    MockCrypto crypto, PeerData mockPeer) {
  return (initialPhase, packages) {
    mockPeer.testedPeer.ourSessionKey = crypto.createKeyStore();
    final sendPubKey = mockPeer.testedPeer.ourSessionKey!.publicKey;
    final phase = mockPeer.sendAndTransitToPhase<InitiatorClientHandshakePhase>(
      message: Key(sendPubKey),
      to: initialPhase,
      encryptWith: crypto.createSharedKeyStore(
          ownKeyStore: mockPeer.permanentKey,
          remotePublicKey: mockPeer.testedPeer.permanentKey!.publicKey),
    );
    final responderData = phase.responders[mockPeer.address]!;
    final responder = responderData.responder;
    expect(responderData.state, equals(State.waitForAuth));
    expect(responder.id, equals(mockPeer.address));
    expect(responder.hasPermanentSharedKey, isTrue);
    final expectedSharedPermanentKey = crypto.createSharedKeyStore(
        ownKeyStore: phase.common.ourKeys,
        remotePublicKey: mockPeer.permanentKey.publicKey);
    expect(responder.permanentSharedKey, same(expectedSharedPermanentKey));
    expect(responder.hasSessionSharedKey, isTrue);
    final decryptWith = crypto.createSharedKeyStore(
        ownKeyStore: mockPeer.permanentKey,
        remotePublicKey: mockPeer.testedPeer.permanentKey!.publicKey);
    final msg =
        mockPeer.expectMessageOfType<Key>(packages, decryptWith: decryptWith);
    final initiatorSessionKey = crypto.getKeyStoreForKey(msg.key)!;
    final expectedSharedSessionKey = crypto.createSharedKeyStore(
      ownKeyStore: initiatorSessionKey,
      remotePublicKey: sendPubKey,
    );
    expect(responder.sessionSharedKey, same(expectedSharedSessionKey));
    mockPeer.testedPeer.theirSessionKey = initiatorSessionKey;
    return phase;
  };
}

Phase Function(Phase, PackageQueue) mkSendBadKeyTest(Crypto crypto,
    {required PeerData responder, required PeerData server}) {
  return (initialPhase, packages) {
    responder.testedPeer.ourSessionKey = crypto.createKeyStore();
    final sendPubKey = responder.testedPeer.ourSessionKey!.publicKey;
    final phase =
        responder.sendAndTransitToPhase<InitiatorClientHandshakePhase>(
            message: Key(sendPubKey),
            to: initialPhase,
            encryptWith: crypto.createSharedKeyStore(
                ownKeyStore: responder.permanentKey,
                remotePublicKey: responder.testedPeer.permanentKey!.publicKey),
            mapEncryptedMessage: (msg) {
              msg.setAll(
                  Nonce.totalLength, Uint8List(msg.length - Nonce.totalLength));
              return msg;
            });
    expect(phase.responders.containsKey(responder.address), isFalse);
    final dropMsg = server.expectMessageOfType<DropResponder>(packages,
        decryptWith: crypto.createSharedKeyStore(
            ownKeyStore: server.testedPeer.theirSessionKey!,
            remotePublicKey: server.testedPeer.ourSessionKey!.publicKey));
    expect(dropMsg.id, equals(responder.address));
    expect(dropMsg.reason, equals(CloseCode.initiatorCouldNotDecrypt));
    return phase;
  };
}

Phase Function(Phase, PackageQueue) mkSendAuthNoSharedTaskTest(
  MockCrypto crypto, {
  required PeerData responder,
  required List<TestTask> tasks,
}) {
  return (phase, packages) {
    try {
      phase = responder.sendAndTransitToPhase<TaskPhase>(
        message: AuthResponder(responder.testedPeer.cookiePair.theirs!, [
          'this is not in the list of tasks',
        ], {
          'this is not in the list of tasks': null,
        }),
        to: phase,
        encryptWith: crypto.createSharedKeyStore(
            ownKeyStore: responder.testedPeer.ourSessionKey!,
            remotePublicKey: responder.testedPeer.theirSessionKey!.publicKey),
      );
      // ignore: empty_catches
    } on NoSharedTaskError {}

    for (final task in tasks) {
      expect(task.initWasCalled, isFalse);
    }

    final msg = responder.expectMessageOfType<Close>(packages,
        decryptWith: crypto.createSharedKeyStore(
            ownKeyStore: responder.testedPeer.ourSessionKey!,
            remotePublicKey: responder.testedPeer.theirSessionKey!.publicKey));

    expect(msg.reason, CloseCode.noSharedTask);

    final channel = (phase.common.sink as MockWebSocket2);
    expect(channel.closeCode, equals(CloseCode.goingAway));

    return phase;
  };
}

Phase Function(Phase, PackageQueue) mkSendAuthTest(
  MockCrypto crypto, {
  required PeerData responder,
  required PeerData server,
  required List<TestTask> tasks,
}) {
  return (initialPhase, packages) {
    final phase = responder.sendAndTransitToPhase<TaskPhase>(
        message: AuthResponder(responder.testedPeer.cookiePair.theirs!, [
          'foobar',
          tasks.last.name,
          'bar foot'
        ], {
          tasks.last.name: tasks.last.data,
          'foobar': null,
          'bar foot': {'dodo': []}
        }),
        to: initialPhase,
        encryptWith: crypto.createSharedKeyStore(
            ownKeyStore: responder.testedPeer.ourSessionKey!,
            remotePublicKey: responder.testedPeer.theirSessionKey!.publicKey));

    for (final task in tasks) {
      if (task.name == tasks.last.name) {
        expect(task.initWasCalled, isTrue);
        expect(phase.task, same(task));
      } else {
        expect(task.initWasCalled, isFalse);
      }
    }

    final authMsg = responder.expectMessageOfType<AuthInitiator>(packages,
        decryptWith: crypto.createSharedKeyStore(
          ownKeyStore: responder.testedPeer.ourSessionKey!,
          remotePublicKey: responder.testedPeer.theirSessionKey!.publicKey,
        ));

    expect(authMsg.yourCookie, responder.testedPeer.cookiePair.ours);
    expect(authMsg.task, equals(tasks.last.name));
    expect(
        authMsg.data,
        equals({
          tasks.last.name: tasks.last.data,
        }));

    var dropMsg = server.expectMessageOfType<DropResponder>(packages,
        decryptWith: crypto.createSharedKeyStore(
          ownKeyStore: server.testedPeer.ourSessionKey!,
          remotePublicKey: server.testedPeer.theirSessionKey!.publicKey,
        ));
    expect(dropMsg.id, equals(Id.responderId(3)));
    expect(dropMsg.reason, equals(CloseCode.droppedByInitiator));

    dropMsg = server.expectMessageOfType<DropResponder>(packages,
        decryptWith: crypto.createSharedKeyStore(
          ownKeyStore: server.testedPeer.ourSessionKey!,
          remotePublicKey: server.testedPeer.theirSessionKey!.publicKey,
        ));
    expect(dropMsg.id, equals(Id.responderId(4)));
    expect(dropMsg.reason, equals(CloseCode.droppedByInitiator));

    return phase;
  };
}

Phase Function(Phase, PackageQueue) mkDropOldOnNewReceiverTest({
  required int newResponderId,
  required int droppedResponderId,
  required PeerData server,
  required Crypto crypto,
}) {
  return (initialPhase, packages) {
    final nrOfResponders =
        phaseAs<InitiatorClientHandshakePhase>(initialPhase).responders.length;
    expect(nrOfResponders, equals(252));
    final newId = Id.responderId(newResponderId);
    final droppedId = Id.responderId(droppedResponderId);
    final phase = server.sendAndTransitToPhase<InitiatorClientHandshakePhase>(
        message: NewResponder(newId),
        to: initialPhase,
        encryptWith: crypto.createSharedKeyStore(
          ownKeyStore: server.testedPeer.theirSessionKey!,
          remotePublicKey: server.testedPeer.ourSessionKey!.publicKey,
        ));

    final dropMsg = server.expectMessageOfType<DropResponder>(packages,
        decryptWith: crypto.createSharedKeyStore(
          ownKeyStore: server.testedPeer.ourSessionKey!,
          remotePublicKey: server.testedPeer.theirSessionKey!.publicKey,
        ));

    expect(dropMsg.id, equals(droppedId));
    expect(phase.responders.keys, contains(newId));
    phase.responders[droppedId];
    expect(phase.responders.length, equals(252));
    return phase;
  };
}