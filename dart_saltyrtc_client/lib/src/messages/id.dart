import 'package:dart_saltyrtc_client/src/messages/validation.dart'
    show
        validateId,
        validateResponderId,
        validateClientId,
        checkClientId,
        checkResponderId;
import 'package:dart_saltyrtc_client/src/protocol/error.dart'
    show ProtocolException;
import 'package:equatable/equatable.dart' show EquatableMixin;
import 'package:meta/meta.dart' show immutable;

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

/// Represent the id of a initiator or a responder.
abstract class ClientId implements Id {}

/// Represent the id of a initiator.
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
      ProtocolException('Id must represent a client id but is $value');
    }
    return this;
  }

  @override
  ResponderId asResponder() {
    if (!isResponder()) {
      ProtocolException('Id must represent a responder id but is $value');
    }
    return this;
  }
}
