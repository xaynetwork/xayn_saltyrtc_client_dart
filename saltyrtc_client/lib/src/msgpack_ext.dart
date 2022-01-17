// Copyright 2021 Xayn AG
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:typed_data' show Uint8List;

import 'package:messagepack/messagepack.dart' show Packer;
import 'package:universal_platform/universal_platform.dart'
    show UniversalPlatform;

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
    } else if (UniversalPlatform.isWeb && any is num) {
      // on web int and double are both num
      // we consider any a double if it is different from itself floored
      // otherwise it is an int. This is what is done by the library that the
      // javascript implementation of the saltyrtc client is using.
      // https://github.com/kawanet/msgpack-lite/blob/5b71d82cad4b96289a466a6403d2faaa3e254167/lib/write-type.js#L57

      // if not finite it can only be encoded as a double
      if (!any.isFinite) {
        packDouble(any.toDouble());
      } else {
        final asInt = any.toInt();
        if (any != asInt) {
          packDouble(any.toDouble());
        } else {
          packInt(asInt);
        }
      }
    } else if (any is double) {
      packDouble(any);
      // we explicitly handle when on web
      // ignore: avoid_double_and_int_checks
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
