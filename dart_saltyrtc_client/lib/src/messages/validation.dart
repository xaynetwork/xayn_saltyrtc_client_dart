import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/src/messages/close_code.dart'
    show CloseCode, CloseCodeToFromInt;
import 'package:dart_saltyrtc_client/src/messages/message.dart'
    show MessageFields;
import 'package:meta/meta.dart' show immutable;

/// Data to instantiate a message is invalid.
@immutable
class ValidationError implements Exception {
  final bool isProtocolError;
  final String _msg;

  ValidationError(this._msg, [this.isProtocolError = false]);

  @override
  String toString() => _msg;
}

/// Check that `value` represent a `type`.
void validateType(dynamic value, String type) {
  if (value is! String) {
    throw ValidationError('Type must be a string');
  }
  if (value != type) {
    throw ValidationError('Type must be $type');
  }
}

/// Check that `value` is a byte array of the expected length.
void validateByteArray(Uint8List value, int expectedLength, String name) {
  if (value.length != expectedLength) {
    throw ValidationError(
        '$name must be $expectedLength bytes long, not ${value.length}');
  }
}

/// Check that `value` is a byte array.
Uint8List validateByteArrayType(dynamic value, String name) {
  if (value is! List<int>) {
    throw ValidationError('$name must be a byte array');
  }
  return Uint8List.fromList(value);
}

/// Check that `value` is a list of `T`.
List<T> validateListType<T>(dynamic value, String name) {
  // TODO can we just check List<T> ? dart types are reified but this come from unpacking messagepack data
  if (value is! List) {
    throw ValidationError('$name must be a list');
  }
  for (final e in value) {
    if (e is! T) {
      throw ValidationError('$name must be a ${T.toString()}');
    }
  }

  return value as List<T>;
}

/// Check that `value` belongs to the interval [min, max].
void validateInteger(int value, int min, int max, String name) {
  if (value < min) {
    throw ValidationError('$name must be >= $min');
  }
  if (value > max) {
    throw ValidationError('$name must be <= $max');
  }
}

/// Check that `value` is a valid id of a peer or a server.
void validateId(int value, String name) {
  validateInteger(value, 0, 255, name);
}

/// Check that `value` is a valid id of a peer.
void validateIdPeer(int value) {
  validateInteger(value, 1, 255, MessageFields.id);
}

/// Check that `value` is a valid id of a responder.
void validateIdResponder(int value, [String name = MessageFields.id]) {
  validateInteger(value, 2, 255, name);
}

/// Check that `value` belongs to `valid`.
void validateIntegerFromList(int value, List<int> valid, String name) {
  if (!valid.contains(value)) {
    throw ValidationError('$name is not valid');
  }
}

/// Check that `value` is an integer.
int validateIntegerType(dynamic value, String name) {
  if (value is! int) {
    throw ValidationError('$name must be an integer');
  }
  return value;
}

/// Validate `value` with `validateType` if `value != null`.
T? validateTypeWithNull<T>(
    dynamic value, String name, T Function(dynamic, String) validateType) {
  if (value != null) {
    return validateType(value!, name);
  }

  return null;
}

/// Check that `value` is an bool.
bool validateBoolType(dynamic value, String name) {
  if (value is! bool) {
    throw ValidationError('$name must be a bool');
  }
  return value;
}

/// Check that `value` is a valid close code.
/// If `dropResponder` is true only the close codes valid when sending
/// a drop-responder message are checked.
///
CloseCode validateCloseCodeType(
    dynamic value, bool dropResponder, String name) {
  if (value is! int) {
    throw ValidationError('$name must be an integer');
  }

  final code = CloseCodeToFromInt.fromInt(value);

  if (dropResponder) {
    const closeCodesDropResponder = [
      CloseCode.protocolError,
      CloseCode.internalError,
      CloseCode.droppedByInitiator,
      CloseCode.initiatorCouldNotDecrypt,
    ];

    if (!closeCodesDropResponder.contains(code)) {
      throw ValidationError('$name must be a valid close code');
    }
  }

  return code;
}

/// Check that task names and task data are both set, and they match.
/// For every task in `tasks` there must be a value `data[task]` and
/// all the keys of `data` must be in `tasks`.
void validateTasksData(
    List<String> tasks, Map<String, Map<String, List<int>>> data) {
  if (tasks.isEmpty) {
    throw ValidationError('Task names must not be empty');
  }
  if (data.isEmpty) {
    throw ValidationError('Task data must not be empty');
  }
  if (data.length != tasks.length) {
    throw ValidationError('Task data must contain an entry for every task');
  }
  if (!tasks.every(data.containsKey)) {
    throw ValidationError('Task data must contain an entry for every task');
  }
}

/// Check that `value` is a string.
String validateStringType(dynamic value, String name) {
  if (value is! String) {
    throw ValidationError('$name must be a string');
  }

  return value;
}

/// Check that `value` is a Map<String, Map<String, List<int>>
Map<String, Map<String, List<int>>> validateStringMapMap(
    dynamic value, String name) {
  // TODO can we just check Map<...> ? dart types are reified but this come from unpacking messagepack data
  if (value is! Map) {
    throw ValidationError('$name must be a Map');
  }

  for (final e in value.entries) {
    if (e.key is! String) {
      throw ValidationError('$name must be a map with strings as keys');
    }
    if (e.value != null && e.value is! Map) {
      throw ValidationError('$name must be a map with maps or null as values');
    }
    for (final MapEntry e in e.value) {
      if (e.key is! String) {
        throw ValidationError('$name must contain maps with string as keys');
      }
      if (e.value is! List<int>) {
        throw ValidationError(
            '$name must contain maps with List<int> as values');
      }
    }
  }

  return value as Map<String, Map<String, List<int>>>;
}
