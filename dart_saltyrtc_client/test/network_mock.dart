import 'dart:async' show StreamController;
import 'dart:collection' show Queue;
import 'dart:typed_data' show Uint8List;

import 'package:async/async.dart' show StreamQueue;
import 'package:dart_saltyrtc_client/src/protocol/network.dart'
    show WebSocketSink, WebSocket;
import 'package:dart_saltyrtc_client/src/protocol/network.dart'
    show WebSocketStream;
import 'package:test/test.dart';

class MockSyncWebSocketSink implements WebSocketSink {
  final queue = PackageQueue();
  int? closeCode;
  String? closeReason;

  @override
  void add(Uint8List package) {
    queue.sendPackage(package);
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) {
    closeCode = closeCode;
    closeReason = closeReason;
    return Future.value(null);
  }
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
  final controller = StreamController<Uint8List>.broadcast();

  /// This is the sink that the client use to send messages to the server.
  @override
  final MockAsyncWebSocketSink sink = MockAsyncWebSocketSink.build();

  /// This is the sink that the client use to receive messages to the server.
  @override
  WebSocketStream get stream => controller.stream;

  Sink<Uint8List> get sinkToClient => controller.sink;
}

class PackageQueue {
  final Queue<Uint8List> queue = Queue();

  void sendPackage(Uint8List package) {
    queue.add(package);
  }

  Uint8List nextPackage() {
    expect(queue, isNotEmpty);
    return queue.removeFirst();
  }

  bool get isEmpty => queue.isEmpty;
}
