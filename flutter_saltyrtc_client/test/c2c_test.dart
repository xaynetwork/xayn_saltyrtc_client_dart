import 'package:test/test.dart';
import 'package:xayn_flutter_saltyrtc_client/events.dart'
    show
        NoSharedTaskFound,
        PeerDisconnected,
        PeerKind,
        SendingMessageToPeerFailed,
        ServerHandshakeDone;
import 'package:xayn_flutter_saltyrtc_client/task.dart'
    show Pair, Task, TaskBuilder, TaskData;

import 'logging.dart' show setUpLogging;
import 'utils.dart' show Setup;

void main() async {
  setUpLogging();

  if (await Setup.skipIntegrationTests()) {
    return;
  }

  test('no shared task found', () async {
    final initiatorSetup = await Setup.initiatorWithAuthToken(
      tasks: [NoTask('no-task.v0'), NoTask('no-task.v2')],
    );

    final responderSetup = await Setup.responderWithAuthToken(
      tasks: [NoTask('no-task.v1'), NoTask('dodo')],
      initiatorTrustedKey: initiatorSetup.client.identity.getPublicKey(),
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
        .timeout(const Duration(seconds: 12));
  });

  test('responder connects first', () async {
    final initiatorSetup = await Setup.initiatorWithAuthToken(
      tasks: [NoTask('no-task.v0'), NoTask('no-task.v2')],
    );

    final responderSetup = await Setup.responderWithAuthToken(
      tasks: [NoTask('no-task.v1'), NoTask('dodo')],
      initiatorTrustedKey: initiatorSetup.client.identity.getPublicKey(),
      authToken: initiatorSetup.authToken!,
    );

    final responderTests = responderSetup.runAndTestEvents([
      (event) => expect(event, equals(ServerHandshakeDone())),
      (event) => expect(event, equals(NoSharedTaskFound())),
    ]);

    await Future<void>.delayed(const Duration(microseconds: 100));

    final initiatorTests = initiatorSetup.runAndTestEvents([
      (event) => expect(event, equals(ServerHandshakeDone())),
      (event) => expect(event, equals(NoSharedTaskFound())),
    ]);

    await Future.wait([initiatorTests, responderTests])
        .timeout(const Duration(seconds: 12));
  });

  test('initiator connects first', () async {
    final initiatorSetup = await Setup.initiatorWithAuthToken(
      tasks: [NoTask('no-task.v0'), NoTask('no-task.v2')],
    );

    final responderSetup = await Setup.responderWithAuthToken(
      tasks: [NoTask('no-task.v1'), NoTask('dodo')],
      initiatorTrustedKey: initiatorSetup.client.identity.getPublicKey(),
      authToken: initiatorSetup.authToken!,
    );

    final initiatorTests = initiatorSetup.runAndTestEvents([
      (event) => expect(event, equals(ServerHandshakeDone())),
      (event) => expect(event, equals(NoSharedTaskFound())),
    ]);

    await Future<void>.delayed(const Duration(microseconds: 100));

    final responderTests = responderSetup.runAndTestEvents([
      (event) => expect(event, equals(ServerHandshakeDone())),
      (event) => expect(event, equals(NoSharedTaskFound())),
    ]);

    await Future.wait([initiatorTests, responderTests])
        .timeout(const Duration(seconds: 12));
  });

  test('responder disconnects and then reconnects', () async {
    final initiatorSetup = await Setup.initiatorWithAuthToken(
      tasks: [NoTask('no-task.v0'), NoTask('no-task.v2')],
    );

    var responderSetup = await Setup.responderWithAuthToken(
      tasks: [NoTask('no-task.v1'), NoTask('dodo')],
      initiatorTrustedKey: initiatorSetup.client.identity.getPublicKey(),
      authToken: initiatorSetup.authToken!,
    );

    final initiatorTests = initiatorSetup.runAndTestEvents([
      (event) => expect(event, equals(ServerHandshakeDone())),
      (event) => expect(
            event,
            anyOf(
              equals(PeerDisconnected(PeerKind.unauthenticated)),
              equals(SendingMessageToPeerFailed(PeerKind.unauthenticated)),
            ),
          ),
      (event) => expect(event, equals(NoSharedTaskFound())),
    ]);

    final event = await responderSetup.client.run().first;
    expect(event, equals(ServerHandshakeDone()));
    responderSetup.client.cancel();

    responderSetup = await Setup.responderWithAuthToken(
      tasks: [NoTask('no-task.v1'), NoTask('dodo')],
      initiatorTrustedKey: initiatorSetup.client.identity.getPublicKey(),
      authToken: initiatorSetup.authToken!,
    );

    final responderTests = responderSetup.runAndTestEvents([
      (event) => expect(event, equals(ServerHandshakeDone())),
      (event) => expect(event, equals(NoSharedTaskFound())),
    ]);

    await Future.wait([initiatorTests, responderTests])
        .timeout(const Duration(seconds: 12));
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
