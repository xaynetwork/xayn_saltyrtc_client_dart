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
