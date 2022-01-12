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

import 'package:equatable/equatable.dart' show EquatableMixin;
import 'package:meta/meta.dart' show immutable;
import 'package:xayn_saltyrtc_client/src/messages/validation.dart'
    show
        validateId,
        validateResponderId,
        validateClientId,
        checkClientId,
        checkResponderId;
import 'package:xayn_saltyrtc_client/src/protocol/error.dart'
    show ProtocolErrorException;

/// Represent an address/id in the saltyrtc protocol.
/// It can only contain values in [0, 255]
@immutable
abstract class Id with EquatableMixin {
  // unknown and server have the same address as specified in the protocol
  static final Id unknownAddress = _AnyId(0);
  static final ServerId serverAddress = _AnyId(0);
  static final InitiatorId initiatorAddress = _AnyId(1);

  /// This is the value of the id and it is guaranteed that it belongs to the range [0, 255]
  abstract final int value;

  @override
  List<Object> get props => [value];

  bool isClient();
  bool isResponder();
  bool isUnknown();
  bool isServer();
  bool isInitiator();

  /// Return the current Id as a client id or throw exception.
  ClientId asClient();

  /// Return the current Id as a responder id or throw exception.
  ResponderId asResponder();

  static Id peerId(int value) {
    validateId(value, 'id');

    return _AnyId(value);
  }

  static ClientId clientId(int value) {
    validateClientId(value);

    return _AnyId(value);
  }

  static ResponderId responderId(int value) {
    validateResponderId(value);

    return _AnyId(value);
  }
}

/// Represent the id of a server.
abstract class ServerId implements Id {}

/// Represent the id of an initiator or a responder.
abstract class ClientId implements Id {}

/// Represent the id of an initiator.
abstract class InitiatorId implements ClientId {}

/// Represent the id of a responder.
abstract class ResponderId implements ClientId {}

class _AnyId with EquatableMixin implements ResponderId, InitiatorId, ServerId {
  @override
  final int value;

  _AnyId(this.value);

  @override
  List<Object> get props => [value];

  @override
  bool isClient() {
    return checkClientId(value);
  }

  @override
  bool isResponder() {
    return checkResponderId(value);
  }

  @override
  bool isUnknown() => this == Id.unknownAddress;

  @override
  bool isServer() => this == Id.serverAddress;

  @override
  bool isInitiator() => this == Id.initiatorAddress;

  @override
  ClientId asClient() {
    if (!isClient()) {
      ProtocolErrorException('Id must represent a client id but is $value');
    }
    return this;
  }

  @override
  ResponderId asResponder() {
    if (!isResponder()) {
      ProtocolErrorException('Id must represent a responder id but is $value');
    }
    return this;
  }
}
