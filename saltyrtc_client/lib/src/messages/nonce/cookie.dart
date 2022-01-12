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

import 'package:equatable/equatable.dart' show EquatableMixin;
import 'package:meta/meta.dart' show immutable;
import 'package:xayn_saltyrtc_client/src/protocol/error.dart'
    show ValidationException;

@immutable
class Cookie with EquatableMixin {
  static const cookieLength = 16;

  final Uint8List _cookie;

  @override
  List<Object> get props => [_cookie];

  Cookie(this._cookie) {
    if (_cookie.length != cookieLength) {
      throw const ValidationException(
        'cookie must be $cookieLength bytes long',
      );
    }
  }

  Cookie.fromRandom(Uint8List Function(int) randomBytes)
      : _cookie = randomBytes(cookieLength);

  Uint8List toBytes() {
    return _cookie;
  }
}
