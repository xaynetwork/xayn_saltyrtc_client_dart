/// Re-export of all types needed to implement a task.
///
/// To implement a task you need to first implement a
/// [TaskBuilder] which is used to build a task and
/// can exchange some initial settings during the
/// client to client handshake.
///
/// Then you need to implement the [Task] created by
/// the [TaskBuilder], especially you need to make sure
/// canceling the task works.
///
/// # Example
///
/// While it in general is strongly recommended to only use the signaling
/// channel for signalling we will use it here to transmit a data blob
/// (to keep thinks simpler).
///
/// ```dart
/// class SendBlobsTaskBuilder extends TaskBuilder {
///  final List<Uint8List> blobs;
///
///  SendBlobsTaskBuilder(this.blobs);
///
///  @override
///  Pair<Task, TaskData?> buildInitiatorTask(TaskData? initialResponderData) {
///    final expectNrMessages = initialResponderData!['nr_messages']! as int;
///    return Pair(
///        SendBlobsTask(expectNrMessages, blobs), {'nr_messages': blobs.length});
///  }
///
///  @override
///  Task buildResponderTask(TaskData? initiatorData) {
///    // preferably do not throw on bad data, instead emit a event
///    // subtype of `ClosingErrorEvent` and call `link.close`.
///    final expectNrMessages = initiatorData!['nr_messages']! as int;
///    return SendBlobsTask(expectNrMessages, blobs);
///  }
///
///  @override
///  TaskData? getInitialResponderData() {
///    return {'nr_messages': blobs.length};
///  }
///
///  @override
///  String get name => 'v1.send-blobs.saltyrtc.xayn.com';
///}
///
///class ReceivedBlob extends Event {
///  final Uint8List blob;
///
///  ReceivedBlob(this.blob);
///
///  @override
///  List<Object?> get props => [blob];
///}
///
///class TaskClosedBeforeDone extends ClosingErrorEvent {}
///
///class SendBlobsTask extends Task {
///  int waitingForNBlobs;
///  List<Uint8List> blobsToSend;
///
///  SendBlobsTask(this.waitingForNBlobs, this.blobsToSend);
///
///  @override
///  void start() {
///    for (final blob in blobsToSend) {
///      link.sendMessage(TaskMessage('blob', {'blob': blob}));
///    }
///  }
///
///  @override
///  void handleCancel(CancelReason reason) {
///    // We didn't do async, I/O, background computation or similar
///    // so not much to do.
///    //
///    // If we e.g. had opened a WebRtc data channel we would close it here.
///
///    // emit an error if we where not done
///    if (waitingForNBlobs > 0) {
///      // In some cases like an internal error this event will not be seen
///      // by anyone as the events channel is already closed. (But a internal
///      // error is seen instead, so you can just emit the event without caring
///      // about such edge cases.)
///      link.emitEvent(TaskClosedBeforeDone());
///    }
///  }
///
///  @override
///  void handleEvent(Event event) {
///    // we don't care about any events emitted for this task
///  }
///
///  @override
///  void handleMessage(TaskMessage msg) {
///    // Again better error handling would be grate
///    switch (msg.type) {
///      case 'blob':
///        final blob = msg.data['blob']! as Uint8List;
///        link.emitEvent(BlobReceived(blob));
///        waitingForNBlobs -= 1;
///        if (waitingForNBlobs == 0) {
///          link.close(CloseCode.closingNormal);
///        }
///        break;
///      default:
///        throw ArgumentError(
///            'only messages of types in `supportedTypes` should be accepted');
///    }
///  }
///
///  @override
///  List<String> get supportedTypes => ['blob'];
///}
///
/// ```
///
library flutter_saltyrtc_client.task;

export 'package:dart_saltyrtc_client/dart_saltyrtc_client.dart'
    show
        Task,
        TaskBuilder,
        CancelReason,
        CloseCode,
        Pair,
        SaltyRtcTaskLink,
        TaskData,
        TaskMessage;
