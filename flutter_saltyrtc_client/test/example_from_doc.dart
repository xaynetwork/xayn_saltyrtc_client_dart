import 'dart:typed_data' show Uint8List;

import 'package:test/test.dart';
import 'package:xayn_flutter_saltyrtc_client/task.dart'
    show
        CancelReason,
        CloseCode,
        Pair,
        Task,
        TaskBuilder,
        TaskData,
        TaskMessage;
import 'package:xayn_saltyrtc_client/events.dart'
    show ClosingErrorEvent, Event, ResponderAuthenticated, ServerHandshakeDone;

import 'logging.dart' show setUpLogging;
import 'task_test.dart' show BlobReceived;
import 'utils.dart' show Setup;

void main() async {
  setUpLogging();

  if (await Setup.skipIntegrationTests()) {
    return;
  }

  final blob1 = Uint8List.fromList([0, 1, 10]);
  final blob2 = Uint8List.fromList([21, 12, 220]);
  final blob3 = Uint8List.fromList([0, 1, 0]);

  test('normal task phase execution works', () async {
    final initiatorSetup = await Setup.initiatorWithAuthToken(
      tasks: [
        SendBlobsTaskBuilder([blob1, blob3])
      ],
    );

    final responderSetup = await Setup.responderWithAuthToken(
      tasks: [
        SendBlobsTaskBuilder([blob3, blob2, blob1])
      ],
      initiatorTrustedKey: initiatorSetup.client.identity.getPublicKey(),
      authToken: initiatorSetup.authToken!,
    );

    final initiatorTests = initiatorSetup.runAndTestEvents([
      (event) => expect(event, equals(ServerHandshakeDone())),
      (event) => expect(
          event,
          equals(ResponderAuthenticated(
              responderSetup.client.identity.getPublicKey()))),
      (event) => expect(event, equals(BlobReceived(blob3))),
      (event) => expect(event, equals(BlobReceived(blob2))),
      (event) => expect(event, equals(BlobReceived(blob1))),
    ]);

    final responderTests = responderSetup.runAndTestEvents([
      (event) => expect(event, equals(ServerHandshakeDone())),
      (event) => expect(
          event,
          equals(ResponderAuthenticated(
              responderSetup.client.identity.getPublicKey()))),
      (event) => expect(event, equals(BlobReceived(blob1))),
      (event) => expect(event, equals(BlobReceived(blob3))),
    ]);

    // more graceful failure/shutdown on timeout
    Future.delayed(Duration(seconds: 10), () {
      responderSetup.client.cancel();
      initiatorSetup.client.cancel();
    });

    await Future.wait([initiatorTests, responderTests]);
  });
}

class SendBlobsTaskBuilder extends TaskBuilder {
  final List<Uint8List> blobs;

  SendBlobsTaskBuilder(this.blobs);

  @override
  Pair<Task, TaskData?> buildInitiatorTask(TaskData? initialResponderData) {
    final expectNrMessages = initialResponderData!['nr_messages']! as int;
    return Pair(
        SendBlobsTask(expectNrMessages, blobs), {'nr_messages': blobs.length});
  }

  @override
  Task buildResponderTask(TaskData? initiatorData) {
    // preferably do not throw on bad data, instead emit an event
    // subtype of `ClosingErrorEvent` and call `link.close`.
    final expectNrMessages = initiatorData!['nr_messages']! as int;
    return SendBlobsTask(expectNrMessages, blobs);
  }

  @override
  TaskData? getInitialResponderData() {
    return {'nr_messages': blobs.length};
  }

  @override
  String get name => 'v1.send-blobs.saltyrtc.xayn.com';
}

class ReceivedBlob extends Event {
  final Uint8List blob;

  ReceivedBlob(this.blob);

  @override
  List<Object?> get props => [blob];
}

class TaskClosedBeforeDone extends ClosingErrorEvent {}

class SendBlobsTask extends Task {
  int waitingForNBlobs;
  List<Uint8List> blobsToSend;

  SendBlobsTask(this.waitingForNBlobs, this.blobsToSend);

  @override
  void start() {
    for (final blob in blobsToSend) {
      link.sendMessage(TaskMessage('blob', {'blob': blob}));
    }
  }

  @override
  void handleCancel(CancelReason reason) {
    // If we had opened a WebRtc data channel we would close it here.

    // emit an error if we were not done
    if (waitingForNBlobs > 0) {
      // In some cases like an internal error this event will not be seen
      // by anyone as the events channel is already closed. (But an internal
      // error is seen instead, so you can just emit the event without caring
      // about such edge cases.)
      link.emitEvent(TaskClosedBeforeDone());
    }
  }

  @override
  void handleEvent(Event event) {
    // we don't care about any events emitted for this task
  }

  @override
  void handleMessage(TaskMessage msg) {
    // Again better error handling would be great
    switch (msg.type) {
      case 'blob':
        final blob = msg.data['blob']! as Uint8List;
        link.emitEvent(BlobReceived(blob));
        waitingForNBlobs -= 1;
        if (waitingForNBlobs == 0) {
          link.close(CloseCode.closingNormal);
        }
        break;
      default:
        throw ArgumentError(
            'only messages of types in `supportedTypes` should be accepted');
    }
  }

  @override
  List<String> get supportedTypes => ['blob'];
}
