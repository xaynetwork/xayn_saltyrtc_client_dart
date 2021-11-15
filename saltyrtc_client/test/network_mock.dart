import 'dart:async' show Completer, EventSink, StreamController;
import 'dart:collection' show Queue;
import 'dart:typed_data' show Uint8List;

import 'package:async/async.dart' show StreamQueue;
import 'package:test/test.dart';
import 'package:xayn_saltyrtc_client/events.dart' show Event;
import 'package:xayn_saltyrtc_client/src/protocol/network.dart'
    show WebSocketSink, WebSocket;
import 'package:xayn_saltyrtc_client/src/protocol/network.dart'
    show WebSocketStream;
import 'package:xayn_saltyrtc_client/src/utils.dart' show Pair;

class MockSyncWebSocketSink implements WebSocketSink {
  final queue = PackageQueue();
  int? closeCode;
  String? closeReason;
  bool isClosed = false;

  @override
  void add(Uint8List package) {
    queue.add(package);
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) {
    isClosed = true;
    this.closeCode = closeCode;
    this.closeReason = closeReason;
    return Future.value(null);
  }
}

class MockSyncWebSocket implements WebSocket {
  @override
  final MockSyncWebSocketSink sink = MockSyncWebSocketSink();

  @override
  int? get closeCode => sink.closeCode;
  set closeCode(int? closeCode) {
    sink.closeCode = closeCode;
  }

  bool get isClosed => sink.isClosed;

  @override
  WebSocketStream get stream => throw UnimplementedError();
}

class MockAsyncWebSocketSink implements WebSocketSink {
  final StreamController<Uint8List> _controller;
  final StreamQueue<Uint8List> queue;
  int? closeCode;
  String? closeReason;

  MockAsyncWebSocketSink._(this._controller, this.queue);

  factory MockAsyncWebSocketSink.build() {
    final controller = StreamController<Uint8List>.broadcast();
    final queue = StreamQueue<Uint8List>(controller.stream);

    return MockAsyncWebSocketSink._(controller, queue);
  }

  @override
  void add(Uint8List package) {
    _controller.add(package);
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) {
    closeCode = closeCode;
    closeReason = closeReason;
    return Future.value(null);
  }
}

class MockWebSocket implements WebSocket {
  final Completer<void> _streamDone = Completer();

  MockWebSocket() {
    stream.listen(null, onDone: () => _streamDone.complete());
  }

  @override
  int? get closeCode => sink.closeCode;

  final controller = StreamController<Uint8List>.broadcast();

  /// This is the sink that the client use to send messages to the server.
  @override
  final MockAsyncWebSocketSink sink = MockAsyncWebSocketSink.build();

  /// This is the sink that the client use to receive messages to the server.
  @override
  WebSocketStream get stream => controller.stream;

  Sink<Uint8List> get sinkToClient => controller.sink;
}

class QueueSink<T> implements EventSink<T> {
  final Queue<Pair<T, bool>> _queue = Queue();
  bool isClosed = false;

  @override
  void add(T data) {
    if (isClosed) {
      throw StateError('QueueSink was already closed');
    }
    _queue.add(Pair(data, false));
  }

  @override
  void addError(Object data, [StackTrace? stackTrace]) {
    if (isClosed) {
      throw StateError('QueueSink was already closed');
    }
    expect(data, isA<T>());
    expect(stackTrace, isNotNull);
    _queue.add(Pair(data as T, true));
  }

  @override
  void close() {
    isClosed = true;
  }

  T next({bool? isError}) {
    final pair = _queue.removeFirst();
    if (isError != null) {
      expect(pair.second, equals(isError));
    }
    return pair.first;
  }

  bool get isEmpty => _queue.isEmpty;

  @override
  String toString() => 'QueueSink($_queue)';
}

class PackageQueue extends QueueSink<Uint8List> {
  @override
  String toString() => 'PackageQueue($_queue)';
}

class EventQueue extends QueueSink<Event> {
  @override
  String toString() => 'EventQueue($_queue)';
}
