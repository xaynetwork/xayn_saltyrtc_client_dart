import 'package:dart_saltyrtc_client/src/messages/validation.dart'
    show
        validateId,
        validateIdResponder,
        validateIdClient,
        checkIdClient,
        checkIdResponder;
import 'package:equatable/equatable.dart' show EquatableMixin;
import 'package:meta/meta.dart' show immutable;

/// Represent an address/id in the saltyrtc protocol.
/// It can only contains values in [0, 255]
@immutable
abstract class Id with EquatableMixin {
  static final Id unknownAddress = Id.peerId(0);
  static final IdServer serverAddress = _Id(0);
  static final IdInitiator initiatorAddress = _Id(1);

  /// this is the value of the id and is guaranteed that belongs to the range [0, 255]
  abstract final int value;

  @override
  List<Object> get props => [value];

  bool isClient();
  bool isResponder();
  bool isUnknown();
  bool isServer();
  bool isInitiator();

  static Id peerId(int value) {
    validateId(value, 'id');

    return _Id(value);
  }

  static IdClient clientId(int value) {
    validateIdClient(value);

    return _Id(value);
  }

  static IdResponder responderId(int value) {
    validateIdResponder(value);

    return _Id(value);
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

class _Id with EquatableMixin implements IdResponder, IdInitiator, IdServer {
  @override
  final int value;

  _Id(this.value);

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
  bool isUnknown() => this == Id.serverAddress;

  @override
  bool isServer() => this == Id.serverAddress;

  @override
  bool isInitiator() => this == Id.serverAddress;
}
