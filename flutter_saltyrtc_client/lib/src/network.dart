// Copyright 2021 Xayn AG
//
// Licensed under the Apache License, Version 2.0 (the License);
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

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
