import 'package:dart_saltyrtc_client/src/messages/validation.dart'
    show
        validateId,
        validateIdResponder,
        validateIdClient,
        checkIdClient,
        checkIdResponder;
import 'package:dart_saltyrtc_client/src/protocol/error.dart'
    show ProtocolError;
import 'package:equatable/equatable.dart' show EquatableMixin;
import 'package:meta/meta.dart' show immutable;

/// Represent an address/id in the saltyrtc protocol.
/// It can only contain values in [0, 255]
@immutable
abstract class Id with EquatableMixin {
  // unknown and server have the same address as specified in the protocol
  static final Id unknownAddress = _AnyId(0);
  static final IdServer serverAddress = _AnyId(0);
  static final IdInitiator initiatorAddress = _AnyId(1);

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
  IdClient asClient();

  /// Return the current Id as a responder id or throw exception.
  IdResponder asIdResponder();

  static Id peerId(int value) {
    validateId(value, 'id');

    return _AnyId(value);
  }

  static IdClient clientId(int value) {
    validateIdClient(value);

    return _AnyId(value);
  }

  static IdResponder responderId(int value) {
    validateIdResponder(value);

    return _AnyId(value);
  }
}

/// Represent the id of a server.
abstract class IdServer implements Id {}

/// Represent the id of a initiator or a responder.
abstract class IdClient implements Id {}

/// Represent the id of a initiator.
abstract class IdInitiator implements IdClient {}

/// Represent the id of a responder.
abstract class IdResponder implements IdClient {}

class _AnyId with EquatableMixin implements IdResponder, IdInitiator, IdServer {
  @override
  final int value;

  _AnyId(this.value);

  @override
  List<Object> get props => [value];

  @override
  bool isClient() {
    return checkIdClient(value);
  }

  @override
  bool isResponder() {
    return checkIdResponder(value);
  }

  @override
  bool isUnknown() => this == Id.unknownAddress;

  @override
  bool isServer() => this == Id.serverAddress;

  @override
  bool isInitiator() => this == Id.initiatorAddress;

  @override
  IdClient asClient() {
    if (!isClient()) {
      ProtocolError('Id must represent a client id but is $value');
    }
    return this;
  }

  @override
  IdResponder asIdResponder() {
    if (!isResponder()) {
      ProtocolError('Id must represent a responder id but is $value');
    }
    return this;
  }
}
