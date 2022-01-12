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

import 'package:messagepack/messagepack.dart' show Packer, Unpacker;
import 'package:test/test.dart';
import 'package:xayn_saltyrtc_client/src/msgpack_ext.dart' show PackAnyExt;

Object? roundTrip(Object? value) {
  final packer = Packer();
  packer.packAny({'value': value});
  final unpacker = Unpacker(packer.takeBytes());
  final map = unpacker.unpackMap();
  return map['value'];
}

void main() {
  group('packAny', () {
    test('is null', () {
      expect(roundTrip(null), isNull);
    });

    test('is int', () {
      expect(roundTrip(12), equals(12));
    });

    test('is double', () {
      expect(roundTrip(1.2), equals(1.2));
    });

    test('is bool', () {
      expect(roundTrip(true), isTrue);
      expect(roundTrip(false), isFalse);
    });

    test('is string', () {
      expect(roundTrip('hy yo'), equals('hy yo'));
    });

    test('is list', () {
      expect(roundTrip([1, 2, 3, 4]), equals([1, 2, 3, 4]));
      expect(roundTrip([1, 'hy', 3, true]), equals([1, 'hy', 3, true]));
    });

    test('is bytes', () {
      expect(
        roundTrip(Uint8List.fromList([1, 2, 3, 4])),
        equals(Uint8List.fromList([1, 2, 3, 4])),
      );
    });

    test('is map', () {
      expect(roundTrip({'hy': 12, 33: null}), equals({'hy': 12, 33: null}));
    });
  });
}
