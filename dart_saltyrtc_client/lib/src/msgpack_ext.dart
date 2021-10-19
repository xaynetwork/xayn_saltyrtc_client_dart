import 'dart:typed_data' show Uint8List;

import 'package:messagepack/messagepack.dart' show Packer;

extension PackAnyExt on Packer {
  /// Tries to pack an arbitrary object.
  ///
  /// Be aware that only `Uint8List` instances are packed as binary and
  /// `List<int>` instances are packed as lists of integers (which is necessary
  /// as we don't know if a `List<int>` is a list of bytes or a list of arbitrary
  /// integers.)
  ///
  void packAny(Object? any) {
    if (any == null) {
      packNull();
    } else if (any is bool) {
      packBool(any);
    } else if (any is double) {
      packDouble(any);
    } else if (any is int) {
      packInt(any);
    } else if (any is String) {
      packString(any);
    } else if (any is Map) {
      packAnyMap(any);
    } else if (any is Uint8List) {
      packBinary(any);
    } else if (any is List) {
      packAnyList(any);
    } else {
      throw ArgumentError('cannot pack objects of type ${any.runtimeType}');
    }
  }

  /// See `packAny`.
  void packAnyMap(Map<Object?, Object?> anyMap) {
    packMapLength(anyMap.length);
    anyMap.forEach((key, value) {
      packAny(key);
      packAny(value);
    });
  }

  /// See `packAny`.
  void packAnyList(List<Object?> anyList) {
    packListLength(anyList.length);
    anyList.forEach(packAny);
  }
}
