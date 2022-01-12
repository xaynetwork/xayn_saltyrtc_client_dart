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

  const ProtocolErrorException(
    this._msg, {
    this.closeCode = CloseCode.protocolError,
  });

  @override
  String toString() => _msg;

  ProtocolErrorException withCloseCode(CloseCode code) =>
      ProtocolErrorException(_msg, closeCode: code);
}

/// Data to instantiate a message is invalid.
@immutable
class ValidationException extends ProtocolErrorException {
  const ValidationException(String msg) : super(msg);
}
