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

import 'package:xayn_saltyrtc_client/src/messages/close_code.dart'
    show CloseCode, CloseCodeToFromInt;
import 'package:xayn_saltyrtc_client/src/messages/message.dart'
    show MessageFields, TaskData, TasksData;
import 'package:xayn_saltyrtc_client/src/protocol/error.dart'
    show ValidationException;

/// Check that `value` represent a `type`.
void validateType(Object? value, String type) {
  if (value is! String) {
    throw const ValidationException(
      'Type must be a string',
    );
  }
  if (value != type) {
    throw ValidationException('Type must be $type');
  }
}

/// Check that `value` represent a string.
String validateTypeType(Object? value) {
  if (value is! String) {
    throw const ValidationException(
      'Type must be a string',
    );
  }

  return value;
}

/// Check that `value` is a byte array of the expected length.
void validateByteArray(Uint8List value, int expectedLength, String name) {
  if (value.length != expectedLength) {
    throw ValidationException(
      '$name must be $expectedLength bytes long, not ${value.length}',
    );
  }
}

/// Check that `value` is a byte array.
Uint8List validateByteArrayType(Object? value, String name) {
  if (value is! List<int>) {
    throw ValidationException('$name must be a byte array');
  }
  return Uint8List.fromList(value);
}

/// Check that `value` is a list of `T`.
List<T> validateListType<T>(Object? value, String name) {
  if (value is! List) {
    throw ValidationException('$name must be a list');
  }
  for (final e in value) {
    if (e is! T) {
      throw ValidationException('$name must be a ${T.toString()}');
    }
  }

  return value.cast<T>();
}

/// Returns true iff the value is in [min, max].
bool checkInteger(int value, int min, int max) {
  return value >= min && value <= max;
}

/// Check that `value` belongs to the interval [min, max].
void validateInteger(int value, int min, int max, String name) {
  if (!checkInteger(value, min, max)) {
    throw ValidationException('$name must be >= $min and <= $max');
  }
}

/// Check that `value` is a valid id of a peer or a server.
void validateId(int value, String name) {
  validateInteger(value, 0, 255, name);
}

bool checkClientId(int value) {
  return checkInteger(value, 1, 255);
}

/// Check that `value` is a valid id of a client.
void validateClientId(int value) {
  validateInteger(value, 1, 255, MessageFields.id);
}

/// Check that `value` is a valid id of a responder.
void validateResponderId(int value, [String name = MessageFields.id]) {
  validateInteger(value, 2, 255, name);
}

/// Check that `value` is a valid id of a responder.
void validateInitiatorId(int value, [String name = MessageFields.id]) {
  validateInteger(value, 1, 1, name);
}

bool checkResponderId(int value) {
  return checkInteger(value, 2, 255);
}

/// Check that `value` belongs to `valid`.
void validateIntegerFromList(int value, List<int> valid, String name) {
  if (!valid.contains(value)) {
    throw ValidationException('$name is not valid');
  }
}

/// Check that `value` is an integer.
int validateIntegerType(Object? value, String name) {
  if (value is! int) {
    throw ValidationException('$name must be an integer');
  }
  return value;
}

/// Validate `value` with `validateType` if `value != null`.
T? validateTypeWithNull<T>(
  Object? value,
  String name,
  T Function(Object?, String) validateType,
) {
  if (value != null) {
    return validateType(value, name);
  }

  return null;
}

/// Check that `value` is an bool.
bool validateBoolType(Object? value, String name) {
  if (value is! bool) {
    throw ValidationException('$name must be a bool');
  }
  return value;
}

/// Check that `value` is a valid close code.
/// If `dropResponder` is true only the close codes valid when sending
/// a drop-responder message are checked.
///
CloseCode validateCloseCodeType(
  Object? value,
  bool dropResponder,
  String name,
) {
  if (value is! int) {
    throw ValidationException('$name must be an integer');
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
      throw ValidationException(
        '$name must be a valid ${dropResponder ? 'drop responder' : ''} close code',
      );
    }
  }

  return code;
}

/// Check that task names and task data are both set, and they match.
/// For every task in `tasks` there must be a value `data[task]` and
/// all the keys of `data` must be in `tasks`.
void validateTasksData(List<String> tasks, TasksData data) {
  if (tasks.isEmpty) {
    throw const ValidationException(
      'Task names must not be empty',
    );
  }
  if (data.isEmpty) {
    throw const ValidationException(
      'Task data must not be empty',
    );
  }
  if (data.length != tasks.length) {
    throw const ValidationException(
      'Task data must contain an entry for every task',
    );
  }
  if (!tasks.every(data.containsKey)) {
    throw const ValidationException(
      'Task data must contain an entry for every task',
    );
  }
}

/// Check that `value` is a string.
String validateStringType(Object? value, String name) {
  if (value is! String) {
    throw ValidationException('$name must be a string');
  }

  return value;
}

/// Check that `value` is a Map<String, Object?>
Map<String, Object?> validateStringMapType(Object? value, String name) {
  if (value is! Map<Object?, Object?>) {
    throw ValidationException('$name must be a Map');
  }

  for (final e in value.entries) {
    if (e.key is! String) {
      throw ValidationException('$name must be a map with strings as keys');
    }
    if (e.value == null) {
      throw ValidationException('$name cannot be null');
    }
  }

  return value.cast<String, Object?>();
}

/// Check that `value` is a Map<String, Object?>
TaskData? validateTaskDataType(Object? value, String name) {
  if (value == null) {
    return null;
  }

  if (value is! Map) {
    throw ValidationException('$name must be a Map');
  }

  for (final e in value.entries) {
    if (e.key is! String) {
      throw ValidationException('$name must be a map with strings as keys');
    }
  }

  return value.cast<String, Object?>();
}

/// Check that `value` is a Map<String, Map<String, List<int>?>?>
TasksData validateTasksDataType(Object? value, String name) {
  final map = <String, TaskData?>{};

  if (value is! Map<Object?, Object?>) {
    throw ValidationException('$name must be a Map');
  }

  for (final e in value.entries) {
    final key = e.key;
    if (key is! String) {
      throw ValidationException('$name must be a map with strings as keys');
    }

    map[key] = validateTaskDataType(e.value, '$name inner');
  }

  return map;
}
