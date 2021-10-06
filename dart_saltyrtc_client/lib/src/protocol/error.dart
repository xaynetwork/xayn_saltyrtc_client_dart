import 'package:dart_saltyrtc_client/src/messages/close_code.dart'
    show CloseCode;
import 'package:meta/meta.dart' show immutable;

@immutable
class ProtocolException implements Exception {
  /// The close code which should be used.
  ///
  /// Default to `protocolError`.
  ///
  /// This is mainly used to communicate decryption failure in 2 specific
  /// places of the client to client handshake.
  final CloseCode closeCode;
  final String _msg;

  ProtocolException(this._msg, {this.closeCode = CloseCode.protocolError});

  @override
  String toString() => _msg;

  ProtocolException withCloseCode(CloseCode code) =>
      ProtocolException(_msg, closeCode: code);
}

/// Data to instantiate a message is invalid.
@immutable
class ValidationException extends ProtocolException {
  ValidationException(String msg) : super(msg);
}
