import 'package:dart_saltyrtc_client/src/messages/close_code.dart';
import 'package:meta/meta.dart' show immutable;

@immutable
class ProtocolError implements Exception {
  final String _msg;

  ProtocolError(this._msg);

  @override
  String toString() => _msg;
}

/// It will result in the connection closing with the specified error code.
@immutable
class SaltyRtcError implements Exception {
  final CloseCode closeCode;
  final String _msg;

  SaltyRtcError(this.closeCode, this._msg);

  @override
  String toString() => _msg;
}

/// Exception used to signal that no shared task was found.
///
@immutable
class NoSharedTaskError extends SaltyRtcError {
  NoSharedTaskError() : super(CloseCode.goingAway, 'no shared task found');
}

/// Data to instantiate a message is invalid.
@immutable
class ValidationError implements Exception {
  final bool isProtocolError;
  final String _msg;

  ValidationError(this._msg, {this.isProtocolError = true});

  @override
  String toString() => _msg;
}

T ensureNotNull<T>(T? o, [String msg = 'Object is null']) {
  if (o == null) {
    throw ProtocolError(msg);
  }

  return o;
}
