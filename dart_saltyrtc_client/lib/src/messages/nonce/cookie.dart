import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/src/protocol/error.dart'
    show ValidationException;
import 'package:equatable/equatable.dart' show EquatableMixin;
import 'package:meta/meta.dart' show immutable;

@immutable
class Cookie with EquatableMixin {
  static const cookieLength = 16;

  final Uint8List _cookie;

  @override
  List<Object> get props => [_cookie];

  Cookie(this._cookie) {
    if (_cookie.length != cookieLength) {
      throw ValidationException('cookie must be $cookieLength bytes long');
    }
  }

  Cookie.fromRandom(Uint8List Function(int) randomBytes)
      : _cookie = randomBytes(cookieLength);

  Uint8List toBytes() {
    return _cookie;
  }
}
