import 'package:meta/meta.dart' show immutable;
import 'package:xayn_saltyrtc_client/src/messages/close_code.dart'
    show CloseCode;

/// It's an Exception representing a ProtocolError.
///
@immutable
class ProtocolErrorException implements Exception {
  /// The close code which should be used.
  ///
  /// Default to `protocolError`.
  ///
  /// This is mainly used to communicate decryption failure in 2 specific
  /// places of the client to client handshake.
  final CloseCode closeCode;
  final String _msg;

  ProtocolErrorException(this._msg, {this.closeCode = CloseCode.protocolError});

  @override
  String toString() => _msg;

  ProtocolErrorException withCloseCode(CloseCode code) =>
      ProtocolErrorException(_msg, closeCode: code);
}

/// Data to instantiate a message is invalid.
@immutable
class ValidationException extends ProtocolErrorException {
  ValidationException(String msg) : super(msg);
}
