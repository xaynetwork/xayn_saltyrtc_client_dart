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
  static final Id serverAddress = Id.peerId(0);
  static final Id initiatorAddress = Id.peerId(1);

  /// This is the value of the id and it is guaranteed that it belongs to the range [0, 255]
  abstract final int value;

  @override
  List<Object> get props => [value];

  bool isClient();
  bool isResponder();

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

/// Represent the id of a initiator or a responder.
abstract class IdClient implements Id {}

abstract class IdResponder implements IdClient {}

class _Id with EquatableMixin implements IdResponder {
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
}
