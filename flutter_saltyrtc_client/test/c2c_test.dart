import 'package:dart_saltyrtc_client/dart_saltyrtc_client.dart'
    show Pair, Task, TaskBuilder, TaskData;
import 'package:flutter_saltyrtc_client/crypto/crypto_provider.dart'
    show getCrypto;
import 'package:flutter_saltyrtc_client/events.dart'
    show NoSharedTaskFound, PeerDisconnected, ServerHandshakeDone, PeerKind;
import 'package:test/test.dart';

import 'logging.dart' show setUpLogging;
import 'utils.dart' show Setup;

void main() {
  setUpLogging();

  test('no shared task found', () async {
    final crypto = await getCrypto();
    await Setup.serverReady();
    final initiatorSetup = Setup.initiatorWithAuthToken(
      crypto,
      tasks: [NoTask('no-task.v0'), NoTask('no-task.v2')],
    );

    final responderSetup = Setup.responderWithAuthToken(
      crypto,
      tasks: [NoTask('no-task.v1'), NoTask('dodo')],
      initiatorTrustedKey: initiatorSetup.permanentKey.publicKey,
      authToken: initiatorSetup.authToken!,
    );

    final initiatorTests = initiatorSetup.runAndTestEvents([
      (event) => expect(event, equals(ServerHandshakeDone())),
      (event) => expect(event, equals(NoSharedTaskFound())),
    ]);

    final responderTests = responderSetup.runAndTestEvents([
      (event) => expect(event, equals(ServerHandshakeDone())),
      (event) => expect(event, equals(NoSharedTaskFound())),
    ]);

    await Future.wait([initiatorTests, responderTests])
        .timeout(Duration(seconds: 12));
  });

  test('responder connects first', () async {
    final crypto = await getCrypto();
    await Setup.serverReady();
    final initiatorSetup = Setup.initiatorWithAuthToken(
      crypto,
      tasks: [NoTask('no-task.v0'), NoTask('no-task.v2')],
    );

    final responderSetup = Setup.responderWithAuthToken(
      crypto,
      tasks: [NoTask('no-task.v1'), NoTask('dodo')],
      initiatorTrustedKey: initiatorSetup.permanentKey.publicKey,
      authToken: initiatorSetup.authToken!,
    );

    final responderTests = responderSetup.runAndTestEvents([
      (event) => expect(event, equals(ServerHandshakeDone())),
      (event) => expect(event, equals(NoSharedTaskFound())),
    ]);

    await Future<void>.delayed(Duration(microseconds: 100));

    final initiatorTests = initiatorSetup.runAndTestEvents([
      (event) => expect(event, equals(ServerHandshakeDone())),
      (event) => expect(event, equals(NoSharedTaskFound())),
    ]);

    await Future.wait([initiatorTests, responderTests])
        .timeout(Duration(seconds: 12));
  });

  test('initiator connects first', () async {
    final crypto = await getCrypto();
    await Setup.serverReady();
    final initiatorSetup = Setup.initiatorWithAuthToken(
      crypto,
      tasks: [NoTask('no-task.v0'), NoTask('no-task.v2')],
    );

    final responderSetup = Setup.responderWithAuthToken(
      crypto,
      tasks: [NoTask('no-task.v1'), NoTask('dodo')],
      initiatorTrustedKey: initiatorSetup.permanentKey.publicKey,
      authToken: initiatorSetup.authToken!,
    );

    final initiatorTests = initiatorSetup.runAndTestEvents([
      (event) => expect(event, equals(ServerHandshakeDone())),
      (event) => expect(event, equals(NoSharedTaskFound())),
    ]);

    await Future<void>.delayed(Duration(microseconds: 100));

    final responderTests = responderSetup.runAndTestEvents([
      (event) => expect(event, equals(ServerHandshakeDone())),
      (event) => expect(event, equals(NoSharedTaskFound())),
    ]);

    await Future.wait([initiatorTests, responderTests])
        .timeout(Duration(seconds: 12));
  });

  test('responder disconnects and then reconnects', () async {
    final crypto = await getCrypto();
    await Setup.serverReady();
    final initiatorSetup = Setup.initiatorWithAuthToken(
      crypto,
      tasks: [NoTask('no-task.v0'), NoTask('no-task.v2')],
    );

    var responderSetup = Setup.responderWithAuthToken(
      crypto,
      tasks: [NoTask('no-task.v1'), NoTask('dodo')],
      initiatorTrustedKey: initiatorSetup.permanentKey.publicKey,
      authToken: initiatorSetup.authToken!,
    );

    final initiatorTests = initiatorSetup.runAndTestEvents([
      (event) => expect(event, equals(ServerHandshakeDone())),
      (event) =>
          expect(event, equals(PeerDisconnected(PeerKind.unauthenticated))),
      (event) => expect(event, equals(NoSharedTaskFound())),
    ]);

    final event = await responderSetup.client.run().first;
    expect(event, equals(ServerHandshakeDone()));
    responderSetup.client.cancel();

    responderSetup = Setup.responderWithAuthToken(
      crypto,
      tasks: [NoTask('no-task.v1'), NoTask('dodo')],
      initiatorTrustedKey: initiatorSetup.permanentKey.publicKey,
      authToken: initiatorSetup.authToken!,
    );

    final responderTests = responderSetup.runAndTestEvents([
      (event) => expect(event, equals(ServerHandshakeDone())),
      (event) => expect(event, equals(NoSharedTaskFound())),
    ]);

    await Future.wait([initiatorTests, responderTests])
        .timeout(Duration(seconds: 12));
  });
}

class NoTask extends TaskBuilder {
  @override
  final String name;

  NoTask(this.name);

  @override
  Pair<Task, TaskData?> buildInitiatorTask(TaskData? initialResponderData) {
    throw UnimplementedError();
  }

  @override
  Task buildResponderTask(TaskData? initiatorData) {
    throw UnimplementedError();
  }

  @override
  TaskData? getInitialResponderData() => {};
}
