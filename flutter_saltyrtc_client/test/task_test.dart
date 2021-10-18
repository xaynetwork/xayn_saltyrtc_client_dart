import 'dart:async' show Completer, Future, Stream, StreamController;
import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/dart_saltyrtc_client.dart'
    show
        CancelReason,
        CloseCode,
        ClosingErrorEvent,
        Event,
        HandoverToTask,
        Pair,
        ResponderAuthenticated,
        SaltyRtcTaskLink,
        ServerHandshakeDone,
        Task,
        TaskBuilder,
        TaskData,
        TaskMessage,
        logger;
import 'package:flutter_saltyrtc_client/flutter_saltyrtc_client.dart';
import 'package:test/test.dart';

import 'logging.dart' show setUpLogging;
import 'utils.dart' show Setup;

void main() {
  setUpLogging();

  // setup clients (initiator and responder)
  // async interleaved do:
  //   - server handshake
  //   - client handshake
  //   - task phase
  test('normal task phase execution works', () async {
    final crypto = await getCrypto();
    await Setup.serverReady();
    final initiatorSetup = Setup.initiatorWithAuthToken(
      crypto,
      tasks: [
        SendBlobTaskBuilder(Uint8List.fromList([1, 2, 3, 4, 123, 43, 2, 1]))
      ],
    );

    final responderSetup = Setup.responderWithAuthToken(
      crypto,
      tasks: [
        SendBlobTaskBuilder(Uint8List.fromList([23, 42, 132]))
      ],
      initiatorTrustedKey: initiatorSetup.permanentPublicKey,
      authToken: initiatorSetup.authToken!,
    );

    final initiatorTests = initiatorSetup.runAndTestEvents([
      (event) => expect(event, equals(ServerHandshakeDone())),
      (event) => expect(event,
          equals(ResponderAuthenticated(responderSetup.permanentPublicKey))),
      (event) => expect(event, equals(HandoverToTask())),
      (event) => expect(
          event, equals(BlobReceived(Uint8List.fromList([23, 42, 132])))),
    ]);

    final responderTests = responderSetup.runAndTestEvents([
      (event) => expect(event, equals(ServerHandshakeDone())),
      (event) => expect(event,
          equals(ResponderAuthenticated(responderSetup.permanentPublicKey))),
      (event) => expect(event, equals(HandoverToTask())),
      (event) => expect(
          event,
          equals(
              BlobReceived(Uint8List.fromList([1, 2, 3, 4, 123, 43, 2, 1])))),
    ]);

    Future.delayed(Duration(seconds: 10), () {
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

  SendBlobTaskBuilder(this.blobToSendOverP2P);

  @override
  Pair<Task, TaskData?> buildInitiatorTask(TaskData? initialResponderData) {
    // An app might use the returned TaskData to exchange information to
    // setup an separate connection, e.g. a WebRTC connection. For simplicity
    // we will use the [FakeP2PChannel] instead.
    expect(initialResponderData, isNotNull);
    expect(initialResponderData!['mode'], equals('magicNetwork'));
    final channel = FakeP2PChannel();
    final data = {'magicId': channel.magicGlobalId, 'mode': 'magicNetwork'};
    return Pair(SendBlobTask._(channel, blobToSendOverP2P), data);
  }

  @override
  Task buildResponderTask(TaskData? initiatorData) {
    expect(initiatorData, isNotNull);
    expect(initiatorData!['mode'], equals('magicNetwork'));
    final magicId = initiatorData['magicId'];
    expect(magicId, isA<int>());
    final channel = FakeP2PChannel();
    channel.connect(magicId as int);
    return SendBlobTask._(channel, blobToSendOverP2P);
  }

  @override
  TaskData? getInitialResponderData() {
    // An app might use the returned TaskData to exchange information to
    // setup an separate connection, e.g. the devices IP address.
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

  SendBlobTask._(this._channel, this._blobToBeSend);

  @override
  void handleCancel(CancelReason reason) {
    logger.d('[$id]handleCancel: $reason');
    close(error: 'canceled: $reason');
  }

  // in this example we can just use the default impl. of following methods:
  // - handleEvent
  // - handleHandover

  @override
  void handleMessage(TaskMessage msg) {
    logger.d('[$id]handleMessage: $msg');
    if (_state == State.waitForReady) {
      switch (msg.type) {
        case 'ready':
          expect(msg.data['ready'], equals('yes'));
          sendBlob();
          logger.d('[$id] requesting handover');
          link.requestHandover();
          return;
      }
    }
    throw StateError('unexpected message of type ${msg.type}');
  }

  @override
  void start(SaltyRtcTaskLink link) {
    logger.d('[$id]start');
    super.start(link);
    _channel.onReady.then((_) {
      logger.d('[$id]sending ready');
      link.sendMessage(TaskMessage('ready', {'ready': 'yes'}));
    });
  }

  // The message is not really necessary but we also want to test sending
  // task messages.
  @override
  List<String> get supportedTypes => ['ready'];

  Future<void> sendBlob() async {
    _channel.sink.add(_blobToBeSend);
    logger.d('[$id]blobSend');
    //pretend it takes a while
    await Future<void>.delayed(Duration(milliseconds: 10));
    final blob = await _channel.stream.first;
    _state = State.done;
    emitEvent(BlobReceived(blob));
    logger.d('[$id]blobReceived');
    close();
  }

  void close({String? error}) {
    logger.d('[$id] error=$error, state=$_state');
    final CloseCode closeCode;
    if (error != null) {
      logger.e(error);
      closeCode = CloseCode.protocolError;
    } else if (_state == State.done) {
      closeCode = CloseCode.closingNormal;
    } else {
      closeCode = CloseCode.goingAway;
    }
    if (_state != State.done && error == null) {
      // This only reaches the client if events hasn't already been closed.
      // Which is fine as in case it is already closed some other error event
      // was already emitted.
      emitEvent(UnexpectedClosedBeforeCompletion());
    }
    if (handoverWasDone) {
      eventsPostHandover!.close();
    } else {
      // Calling close even after a handover is fine,
      // it will simply have no effect.
      link.close(closeCode);
    }
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
