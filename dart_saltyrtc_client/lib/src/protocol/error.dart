import 'package:meta/meta.dart' show immutable;

@immutable
class ProtocolError implements Exception {
  final String _msg;

  ProtocolError(this._msg);

  @override
  String toString() => _msg;
}

T ensureNotNull<T extends Object?>(T o, [String msg = 'Object is null']) {
  if (o == null) {
    throw ProtocolError(msg);
  }

  return o;
}
