import 'dart:collection' show Queue;
import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/src/protocol/network.dart'
    show WebSocketSink;

import 'package:test/test.dart';

class MockWebSocket implements WebSocketSink {
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

  Uint8List nextPackage() {
    expect(queue, isNotEmpty);
    return queue.removeFirst();
  }

  bool get isEmpty => queue.isEmpty;
}
