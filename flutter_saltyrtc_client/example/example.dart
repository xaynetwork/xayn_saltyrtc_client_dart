import 'dart:typed_data' show Uint8List;

import 'package:hex/hex.dart' show HEX;
import 'package:xayn_flutter_saltyrtc_client/task.dart'
    show
        CancelReason,
        CloseCode,
        Pair,
        Task,
        TaskBuilder,
        TaskData,
        TaskMessage;
import 'package:xayn_flutter_saltyrtc_client/xayn_flutter_saltyrtc_client.dart';
import 'package:xayn_saltyrtc_client/events.dart'
    show ClosingErrorEvent, Event, ResponderAuthenticated, ServerHandshakeDone;

/// This example define a task that sends binary blobs from one device to the other.
Future<void> main() async {
  const int pingInterval = 60;
  final serverUri = Uri.parse('ws://localhost:8765');
  final serverPublicKey = Uint8List.fromList(
    HEX.decode(
      '09a59a5fa6b45cb07638a3a6e347ce563a948b756fd22f9527465f7c79c2a864',
    ),
  );

  // blobs that we want to send from one device to the other
  final blob1 = Uint8List.fromList([0, 1, 10]);
  final blob2 = Uint8List.fromList([21, 12, 220]);
  final blob3 = Uint8List.fromList([0, 1, 0]);

  // we simulate a first pairing, so we generate a fresh auth token.
  // it can be used only for one connection to the server, after that we should have
  // the responder public key or we need to generate a new one.
  // this needs to be transferred to the responder using a secure side channel.
  final authTokenBytes = await InitiatorClient.createAuthToken();

  // configure initiator

  // this is the permanent key of the initiator for this pair of devices.
  // it can be recreated with [Identity.fromRawKeys].
  final initiatorIdentity = await Identity.newIdentity();

  final initiatorClient = await InitiatorClient.withUntrustedResponder(
    serverUri,
    [
      SendBlobsTaskBuilder([blob1, blob3])
    ],
    pingInterval: pingInterval,
    expectedServerKey: serverPublicKey,
    sharedAuthToken: authTokenBytes,
    identity: initiatorIdentity,
  );

  // run the internal client loop and get a stream of events
  final initiatorEvents = initiatorClient.run();

  // configure responder

  // this is the permanent key of the responder for this pair of devices.
  final responderIdentity = await Identity.newIdentity();

  // this information will need to be transferred using a secure side channel.
  final initiatorTrustedPublicKey = initiatorIdentity.getPublicKey();

  final responderClient = await ResponderClient.withAuthToken(
    serverUri,
    [
      SendBlobsTaskBuilder([blob3, blob2, blob1])
    ],
    pingInterval: pingInterval,
    expectedServerKey: serverPublicKey,
    initiatorTrustedKey: initiatorTrustedPublicKey,
    sharedAuthToken: authTokenBytes,
    identity: responderIdentity,
  );

  final responderEvents = responderClient.run();

  // handling event for the initiator
  initiatorEvents.listen((event) {
    if (event is ServerHandshakeDone) {
      print(
        'Initiator is connected to the server and is waiting for a responder to connect',
      );
    }

    if (event is ResponderAuthenticated) {
      print(
        'Responder authenticated',
      );
      // we throw away the authentication token and we safely store the responder public,
      // we will use it for all future connections.
    }

    if (event is BlobReceived) {
      print(
        'Initiator received blob',
      );
    }
  });

  // handling event for the responder
  responderEvents.listen((event) {
    if (event is ServerHandshakeDone) {
      print(
        'Responder is connected to the server and is waiting for an initiator to connect',
      );
    }

    // even if we are the responder we still get this event
    if (event is ResponderAuthenticated) {
      print(
        'Responder authenticated',
      );
      // now we know that the initiator received our public key and we should
      // use that for all future connections.
    }

    if (event is BlobReceived) {
      print(
        'Responder received blob',
      );
    }
  });
}

// we define a custom event that the task can use
// to communicate back to the application
class BlobReceived extends Event {
  final Uint8List blob;

  BlobReceived(this.blob);

  @override
  List<Object?> get props => [blob];
}

class TaskClosedBeforeDone extends ClosingErrorEvent {}

class SendBlobsTaskBuilder extends TaskBuilder {
  final List<Uint8List> blobs;

  SendBlobsTaskBuilder(this.blobs);

  @override
  Pair<Task, TaskData?> buildInitiatorTask(TaskData? initialResponderData) {
    final expectNrMessages = initialResponderData!['nr_messages']! as int;
    return Pair(
      SendBlobsTask(expectNrMessages, blobs),
      {'nr_messages': blobs.length},
    );
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
        final blob = Uint8List.fromList(msg.data['blob']! as List<int>);
        link.emitEvent(BlobReceived(blob));
        waitingForNBlobs -= 1;
        if (waitingForNBlobs == 0) {
          link.close(CloseCode.closingNormal);
        }
        break;
      default:
        throw ArgumentError(
          'only messages of types in `supportedTypes` should be accepted',
        );
    }
  }

  @override
  List<String> get supportedTypes => ['blob'];
}
