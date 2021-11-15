import 'dart:typed_data' show Uint8List;

import 'package:web_socket_channel/web_socket_channel.dart' as websocket
    show WebSocketSink, WebSocketChannel;
import 'package:xayn_saltyrtc_client/xayn_saltyrtc_client.dart' as saltyrtc
    show WebSocketSink, WebSocket, WebSocketStream;

/// Wrap websocket.WebSocketChannel to implement saltyrtc.WebSocket.
class WebSocket implements saltyrtc.WebSocket {
  final websocket.WebSocketChannel _ws;
  @override
  final WebSocketSink sink;

  WebSocket(this._ws) : sink = WebSocketSink(_ws.sink);

  @override
  saltyrtc.WebSocketStream get stream => _ws.stream.cast();

  @override
  int? get closeCode => _ws.closeCode;
}

/// Wrap websocket.WebSocketSink to implement saltyrtc.WebSocketSink.
class WebSocketSink implements saltyrtc.WebSocketSink {
  final websocket.WebSocketSink _ws;

  WebSocketSink(this._ws);

  @override
  void add(Uint8List data) {
    _ws.add(data);
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) {
    return _ws.close(closeCode, closeReason);
  }
}
