import 'dart:async' show Completer, Future, Stream, StreamController;
import 'dart:typed_data' show Uint8List;

import 'package:test/test.dart';
import 'package:xayn_flutter_saltyrtc_client/events.dart'
    show
        ClosingErrorEvent,
        Event,
        HandoverToTask,
        ResponderAuthenticated,
        ServerHandshakeDone;
import 'package:xayn_flutter_saltyrtc_client/task.dart'
    show
        CancelReason,
        CloseCode,
        Pair,
        Task,
        TaskBuilder,
        TaskData,
        TaskMessage;
import 'package:xayn_saltyrtc_client/xayn_saltyrtc_client.dart'
    show saltyRtcClientLibLogger;

import 'logging.dart' show setUpLogging;
import 'utils.dart' show Setup;

void main() async {
  setUpLogging();

  if (await Setup.skipIntegrationTests()) {
    return;
  }

  test('normal task phase execution works', () async {
    final initiatorSetup = await Setup.initiatorWithAuthToken(
      tasks: [
        SendBlobTaskBuilder(Uint8List.fromList([1, 2, 3, 4, 123, 43, 2, 1]))
      ],
    );

    final responderSetup = await Setup.responderWithAuthToken(
      tasks: [
        SendBlobTaskBuilder(Uint8List.fromList([23, 42, 132]))
      ],
      initiatorTrustedKey: initiatorSetup.client.identity.getPublicKey(),
      authToken: initiatorSetup.authToken!,
    );

    final initiatorTests = initiatorSetup.runAndTestEvents([
      (event) => expect(event, equals(ServerHandshakeDone())),
      (event) => expect(
            event,
            equals(
              ResponderAuthenticated(
                responderSetup.client.identity.getPublicKey(),
              ),
            ),
          ),
      (event) => expect(event, equals(HandoverToTask())),
      (event) => expect(
            event,
            equals(BlobReceived(Uint8List.fromList([23, 42, 132]))),
          ),
    ]);

    final responderTests = responderSetup.runAndTestEvents([
      (event) => expect(event, equals(ServerHandshakeDone())),
      (event) => expect(
            event,
            equals(
              ResponderAuthenticated(
                responderSetup.client.identity.getPublicKey(),
              ),
            ),
          ),
      (event) => expect(event, equals(HandoverToTask())),
      (event) => expect(
            event,
            equals(
              BlobReceived(Uint8List.fromList([1, 2, 3, 4, 123, 43, 2, 1])),
            ),
          ),
    ]);

    // more graceful failure/shutdown on timeout
    Future.delayed(Duration(seconds: 10), () {
      responderSetup.client.cancel();
      initiatorSetup.client.cancel();
    });

    await Future.wait([initiatorTests, responderTests]);
  });

  test('cancel after handover works', () async {
    final initiatorSetup = await Setup.initiatorWithAuthToken(
      tasks: [
        SendBlobTaskBuilder(
          Uint8List.fromList([1, 2, 3, 4, 123, 43, 2, 1]),
          hang: true,
        )
      ],
    );

    final responderSetup = await Setup.responderWithAuthToken(
      tasks: [
        SendBlobTaskBuilder(Uint8List.fromList([23, 42, 132]), hang: true)
      ],
      initiatorTrustedKey: initiatorSetup.client.identity.getPublicKey(),
      authToken: initiatorSetup.authToken!,
    );

    final initiatorTests = initiatorSetup.runAndTestEvents([
      (event) => expect(event, equals(ServerHandshakeDone())),
      (event) => expect(
            event,
            equals(
              ResponderAuthenticated(
                responderSetup.client.identity.getPublicKey(),
              ),
            ),
          ),
      (event) => expect(event, equals(HandoverToTask())),
      (event) => expect(event, equals(UnexpectedClosedBeforeCompletion())),
    ]);

    final responderTests = responderSetup.runAndTestEvents([
      (event) => expect(event, equals(ServerHandshakeDone())),
      (event) => expect(
            event,
            equals(
              ResponderAuthenticated(
                responderSetup.client.identity.getPublicKey(),
              ),
            ),
          ),
      (event) => expect(event, equals(HandoverToTask())),
      (event) => expect(event, equals(UnexpectedClosedBeforeCompletion())),
    ]);

    Future.delayed(Duration(milliseconds: 100), () {
      responderSetup.client.cancel();
      initiatorSetup.client.cancel();
    });

    await Future.wait([initiatorTests, responderTests])
        .timeout(Duration(seconds: 12));
  });
}

class BlobReceived extends Event {
  final Uint8List blob;

  BlobReceived(this.blob);

  @override
  List<Object?> get props => [blob];
}

class UnexpectedClosedBeforeCompletion extends ClosingErrorEvent {}

class SendBlobTaskBuilder extends TaskBuilder {
  final Uint8List blobToSendOverP2P;
  final bool hang;

  SendBlobTaskBuilder(this.blobToSendOverP2P, {this.hang = false});

  @override
  Pair<Task, TaskData?> buildInitiatorTask(TaskData? initialResponderData) {
    // An app might use the returned TaskData to exchange information to
    // setup an separate connection, e.g. a WebRTC connection. For simplicity
    // we will use the [FakeP2PChannel] instead.
    expect(initialResponderData, isNotNull);
    expect(initialResponderData!['mode'], equals('magicNetwork'));
    final channel = FakeP2PChannel();
    final data = {'magicId': channel.magicGlobalId, 'mode': 'magicNetwork'};
    return Pair(SendBlobTask._(channel, blobToSendOverP2P, hang: hang), data);
  }

  @override
  Task buildResponderTask(TaskData? initiatorData) {
    expect(initiatorData, isNotNull);
    expect(initiatorData!['mode'], equals('magicNetwork'));
    final magicId = initiatorData['magicId'];
    expect(magicId, isA<int>());
    final channel = FakeP2PChannel();
    channel.connect(magicId as int);
    return SendBlobTask._(channel, blobToSendOverP2P, hang: hang);
  }

  @override
  TaskData? getInitialResponderData() {
    // Tasks can use task data to exchange settings.
    return {'mode': 'magicNetwork'};
  }

  @override
  String get name => 'xayn.send-blob.v0';
}

enum State { waitForReady, readyReceived, done }

class SendBlobTask extends Task {
  static int _idGen = 0;

  final int id = _idGen++;
  final FakeP2PChannel _channel;
  final Uint8List _blobToBeSend;
  State _state = State.waitForReady;
  final bool hang;
  bool handoverWasDone = false;

  SendBlobTask._(this._channel, this._blobToBeSend, {this.hang = false});

  @override
  void handleCancel(CancelReason reason) {
    saltyRtcClientLibLogger.d('[$id]handleCancel: $reason');
    close();
  }

  @override
  void handleEvent(Event event) {
    if (event is HandoverToTask) {
      saltyRtcClientLibLogger.d('[$id] handover done');
    }
  }

  @override
  void handleMessage(TaskMessage msg) {
    saltyRtcClientLibLogger.d('[$id]handleMessage: $msg');
    if (_state == State.waitForReady) {
      switch (msg.type) {
        case 'ready':
          expect(msg.data['ready'], equals('yes'));
          sendBlob();
          saltyRtcClientLibLogger.d('[$id] requesting handover');
          link.requestHandover();
          return;
      }
    }
    throw StateError('unexpected message of type ${msg.type}');
  }

  @override
  void start() {
    saltyRtcClientLibLogger.d('[$id]start');
    _channel.onReady.then((_) {
      saltyRtcClientLibLogger.d('[$id]sending ready');
      link.sendMessage(TaskMessage('ready', const {'ready': 'yes'}));
    });
  }

  // A message for testing.
  @override
  List<String> get supportedTypes => ['ready'];

  Future<void> sendBlob() async {
    if (hang) {
      await Future<void>.delayed(Duration(seconds: 20));
    }
    _channel.sink.add(_blobToBeSend);
    saltyRtcClientLibLogger.d('[$id]blobSend');
    //pretend it takes a while
    await Future<void>.delayed(Duration(milliseconds: 10));
    final blob = await _channel.stream.first;
    _state = State.done;
    link.emitEvent(BlobReceived(blob));
    saltyRtcClientLibLogger.d('[$id]blobReceived');
    close();
  }

  void close() {
    saltyRtcClientLibLogger.d('[$id] closing on state=$_state');
    final CloseCode closeCode;
    if (_state == State.done) {
      closeCode = CloseCode.closingNormal;
    } else {
      closeCode = CloseCode.goingAway;
    }
    if (_state != State.done) {
      // This only reaches the client if events hasn't already been closed.
      // Which is fine as in case it is already closed some other error event
      // was already emitted.
      link.emitEvent(UnexpectedClosedBeforeCompletion());
    }
    link.close(closeCode);
    _channel.sink.close();
  }
}

class FakeP2PChannel {
  static int _magicGlobalIdGen = 0;
  static final Map<int, FakeP2PChannel> _magicNetwork = {};

  Stream<Uint8List>? _stream;
  Stream<Uint8List> get stream => _stream!;
  Sink<Uint8List>? _sink;
  Sink<Uint8List> get sink => _sink!;

  final int magicGlobalId = _magicGlobalIdGen++;

  final Completer<void> _onReady = Completer();
  Future<void> get onReady => _onReady.future;

  FakeP2PChannel() {
    _magicNetwork[magicGlobalId] = this;
  }

  void connect(int magicId) {
    final other = _magicNetwork[magicId]!;
    final outgoing = StreamController<Uint8List>();
    expect(_sink, isNull);
    expect(other._stream, isNull);
    _sink = outgoing.sink;
    other._stream = outgoing.stream;

    final incomming = StreamController<Uint8List>();
    expect(_stream, isNull);
    expect(other._sink, isNull);
    _stream = incomming.stream;
    other._sink = incomming.sink;

    _onReady.complete();
    other._onReady.complete();
  }
}
