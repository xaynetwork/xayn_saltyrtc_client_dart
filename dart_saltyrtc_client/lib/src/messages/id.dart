import 'package:dart_saltyrtc_client/src/messages/validation.dart'
    show validateId, validateIdResponder, validateIdPeer;
import 'package:equatable/equatable.dart' show EquatableMixin;
import 'package:meta/meta.dart' show immutable;

/// Represent an address/id in the saltyrtc protocol.
/// It can only contains values in [0, 255]
@immutable
class Id with EquatableMixin {
  static final Id serverAddress = Id(0);
  static final Id initiatorAddress = Id(1);

  /// this is the value of the id and is guaranteed that belongs to the range [0, 255]
  final int value;

  @override
  List<Object> get props => [value];

  Id(this.value) {
    validateId(value, 'id');
  }

  factory Id.ofResponder(int id) {
    return IdResponder(id);
  }
}

// TODO find a way to avoid repeating the checks on every super.
// @protected on constructors does not give a warning

class IdPeer extends Id {
  IdPeer(int id) : super(id) {
    validateIdPeer(id);
  }
}

class IdResponder extends IdPeer {
  IdResponder(int id) : super(id) {
    validateIdResponder(id);
  }
}
