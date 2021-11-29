import 'dart:typed_data' show Uint8List;

import 'package:fixnum/fixnum.dart' show Int64;
import 'package:test/test.dart';
import 'package:xayn_saltyrtc_client/src/messages/nonce/combined_sequence.dart'
    show CombinedSequence, OverflowException;

extension ToInt64 on CombinedSequence {
  Int64 toInt64() {
    final bytes = Uint8List(8);
    bytes.setAll(2, toBytes());
    return Int64.fromBytesBigEndian(bytes);
  }
}

void main() {
  test('Max combined sequence number', () {
    expect(CombinedSequence.combinedSequenceNumberMax, (Int64.ONE << 48) - 1);
  });

  test('From random', () {
    final cs = CombinedSequence.fromRandom(
      (size) => Uint8List.fromList(List.filled(size, 255)),
    );

    expect(
      cs.toInt64(),
      lessThanOrEqualTo(CombinedSequence.combinedSequenceNumberMax),
    );
    expect(cs.isOverflowZero, true);
  });

  test('From Int64', () {
    final shifts = List<int>.generate(41, (i) => i);
    for (final shift in shifts) {
      final source = Int64(255) << shift;
      final cs = CombinedSequence(source);
      expect(cs.toInt64(), source);
    }
  });

  test('From bytes', () {
    final shifts = List<int>.generate(41, (i) => i);
    for (final shift in shifts) {
      final source = Int64(255) << shift;
      final csSource = CombinedSequence(source);
      final cs = CombinedSequence.fromBytes(csSource.toBytes());
      expect(cs, csSource);
    }
  });

  test('isOverflowZero', () {
    final overflowShifts = List<int>.generate(16, (i) => i + 32);
    for (final shift in overflowShifts) {
      final num = Int64.ONE << shift;
      final cs = CombinedSequence(num);
      expect(cs.isOverflowZero, false);
    }
  });

  test('next', () {
    final maxSequenceNumber = (Int64.ONE << 32) - 1;
    final cs = CombinedSequence(maxSequenceNumber);
    cs.next();
    expect(cs.isOverflowZero, false);
    expect(cs.toBytes(), [0, 1, 0, 0, 0, 0]);
  });

  test('next overflow', () {
    final cs = CombinedSequence(CombinedSequence.combinedSequenceNumberMax);
    expect(() => cs.next(), throwsA(isA<OverflowException>()));
  });

  test('toBytes max', () {
    final cs = CombinedSequence(CombinedSequence.combinedSequenceNumberMax);
    final bytes = cs.toBytes();
    expect(CombinedSequence.numBytes, 6);
    expect(bytes.length, CombinedSequence.numBytes);
    expect(bytes, everyElement(equals(255)));
  });

  test('toBytes sequence max', () {
    final cs = CombinedSequence((Int64.ONE << 32) - 1);
    final bytes = cs.toBytes();
    expect(CombinedSequence.numBytes, 6);
    expect(bytes.length, CombinedSequence.numBytes);
    expect(bytes.sublist(0, 2), everyElement(equals(0)));
    expect(bytes.sublist(2), everyElement(equals(255)));
  });
}
