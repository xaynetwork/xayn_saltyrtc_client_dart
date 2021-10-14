import 'package:dart_saltyrtc_client/src/messages/close_code.dart'
    show CloseCode;
import 'package:meta/meta.dart' show immutable;

@immutable
class ProtocolError implements Exception {
  /// The close code which should be used.
  ///
  /// Default to `protocolError`.
  ///
  /// This is mainly used to communicate decryption failure in 2 specific
  /// places of the client to client handshake.
  final CloseCode closeCode;
  final String _msg;

  ProtocolError(this._msg, {this.closeCode = CloseCode.protocolError});

  @override
  String toString() => _msg;

  ProtocolError withCloseCode(CloseCode code) =>
      ProtocolError(_msg, closeCode: code);
}

/// Data to instantiate a message is invalid.
@immutable
class ValidationError extends ProtocolError {
  ValidationError(String msg) : super(msg);
}
