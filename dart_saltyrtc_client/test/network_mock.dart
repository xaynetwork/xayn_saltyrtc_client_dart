import 'dart:async' show StreamController, FutureOr, StreamSink;
import 'dart:collection' show Queue;
import 'dart:typed_data' show Uint8List, Endian;

import 'package:dart_saltyrtc_client/src/protocol/network.dart'
    show WebSocketSink, WebSocketStream;

import 'package:test/test.dart';

class MockWebSocket2 implements WebSocketSink {
  final PackageQueue queue = PackageQueue();
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

class PackageQueue {
  final Queue<Uint8List> queue = Queue();

  void sendPackage(Uint8List package) {
    queue.add(package);
  }

  Uint8List takeNextPackage() {
    expect(queue, isNotEmpty);
    return queue.removeFirst();
  }

  bool get isEmpty => queue.isEmpty;
}

class MockWebSocket implements StreamController<Uint8List>, WebSocketSink {
  final StreamController<Uint8List> _controller = StreamController<Uint8List>();

  @override
  FutureOr<void> Function()? get onCancel => _controller.onCancel;

  @override
  set onCancel(FutureOr<void> Function()? _onCancel) {
    _controller.onCancel = _onCancel;
  }

  @override
  void Function()? get onListen => _controller.onListen;

  @override
  set onListen(void Function()? _onListen) {
    _controller.onListen = _onListen;
  }

  @override
  void Function()? get onPause => _controller.onPause;

  @override
  set onPause(void Function()? _onPause) {
    _controller.onPause = _onPause;
  }

  @override
  void Function()? get onResume => _controller.onResume;

  @override
  set onResume(void Function()? _onResume) {
    _controller.onResume = _onResume;
  }

  @override
  void add(Uint8List event) {
    _controller.add(event);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    _controller.addError(error, stackTrace);
  }

  @override
  Future addStream(Stream<Uint8List> source, {bool? cancelOnError}) {
    return _controller.addStream(source, cancelOnError: cancelOnError);
  }

  @override
  Future close([int? closeCode, String? closeReason]) {
    // we encode the close message as 2 bytes for the closeCode
    // the protocol does not prescribe to send a close reason so we can ignore it
    // TODO check that we are reading the correct bytes
    final closeCodeBytes = Uint8List(2)
      ..buffer.asByteData().setInt16(0, closeCode ?? 0, Endian.big);
    add(closeCodeBytes);
    return _controller.close();
  }

  @override
  Future get done => _controller.done;

  @override
  bool get hasListener => _controller.hasListener;

  @override
  bool get isClosed => _controller.isClosed;

  @override
  bool get isPaused => _controller.isPaused;

  @override
  StreamSink<Uint8List> get sink => _controller.sink;

  @override
  WebSocketStream get stream => _controller.stream;
}
