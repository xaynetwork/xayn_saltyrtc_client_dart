import 'dart:typed_data' show Uint8List;

// the main difference between this classes and the on in the
// web_socket_channel library is that here we are enforcing to send an receive bytes

/// Represent a Websocket sink that can be closed by passing a close code and reason.
abstract class WebSocketSink implements Sink<Uint8List> {
  /// Closes the web socket connection.
  ///
  /// closeCode and closeReason are the close code and reason sent to
  /// the remote peer, respectively. If they are omitted, the peer will see a
  /// "no status received" code with no reason.
  @override
  Future close([int? closeCode, String? closeReason]);
}

typedef WebSocketStream = Stream<Uint8List>;
