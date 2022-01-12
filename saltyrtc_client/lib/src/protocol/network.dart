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

// the main difference between this classes and the on in the
// web_socket_channel library is that here we are enforcing to send an receive bytes
// while the one in web_socket_channel accept a dynamic and depending on the typ
// it decide if it has to send a Text or a Binary message

/// Represent a Websocket sink that can be closed by passing a close code and reason.
abstract class WebSocketSink implements Sink<Uint8List> {
  /// Closes the web socket connection.
  ///
  /// closeCode and closeReason are the close code and reason sent to
  /// the remote peer, respectively. If they are omitted, the peer will see a
  /// "no status received" code with no reason.
  @override
  Future<void> close([int? closeCode, String? closeReason]);
}

typedef WebSocketStream = Stream<Uint8List>;

abstract class WebSocket {
  /// The code used to close the web socket (if there was one and if the
  /// socket was closed)
  int? get closeCode;

  WebSocketSink get sink;
  WebSocketStream get stream;
}
