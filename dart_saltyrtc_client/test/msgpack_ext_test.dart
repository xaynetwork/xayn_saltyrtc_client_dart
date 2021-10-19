import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/src/msgpack_ext.dart' show PackAnyExt;
import 'package:messagepack/messagepack.dart' show Packer, Unpacker;
import 'package:test/test.dart';

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
      expect(roundTrip(Uint8List.fromList([1, 2, 3, 4])),
          equals(Uint8List.fromList([1, 2, 3, 4])));
    });

    test('is map', () {
      expect(roundTrip({'hy': 12, 33: null}), equals({'hy': 12, 33: null}));
    });
  });
}
