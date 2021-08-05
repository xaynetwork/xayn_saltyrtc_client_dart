import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/src/messages/nonce/combined_sequence.dart';
import 'package:dart_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;
import 'package:dart_saltyrtc_client/src/messages/validation.dart'
    show ValidationError;
import 'package:fixnum/fixnum.dart' show Int64;
import 'package:test/test.dart';

void main() {
  test('nonce length', () {
    expect(Nonce.totalLength, 24);
  });

  test('cookie length', () {
    expect(Nonce.cookieLength, 16);
  });

  test('valid cookie', () {
    final cs = CombinedSequence(Int64.ZERO);

    final cookieShort = Uint8List(Nonce.cookieLength - 1);
    expect(() => Nonce(cookieShort, cs, 1, 1), throwsA(isA<ValidationError>()));

    final cookieLong = Uint8List(Nonce.cookieLength + 1);
    expect(() => Nonce(cookieLong, cs, 1, 1), throwsA(isA<ValidationError>()));

    Nonce(Uint8List(Nonce.cookieLength), cs, 1, 1);
  });

  test('valid source', () {
    final cs = CombinedSequence(Int64.ZERO);
    final cookie = Uint8List(Nonce.cookieLength);

    expect(() => Nonce(cookie, cs, -1, 1), throwsA(isA<ValidationError>()));
    expect(() => Nonce(cookie, cs, 256, 1), throwsA(isA<ValidationError>()));

    for (final source in List.generate(255, (i) => i)) {
      Nonce(cookie, cs, source, 1);
    }
  });

  test('valid destination', () {
    final cs = CombinedSequence(Int64.ZERO);
    final cookie = Uint8List(Nonce.cookieLength);

    expect(() => Nonce(cookie, cs, 1, -1), throwsA(isA<ValidationError>()));
    expect(() => Nonce(cookie, cs, 1, 256), throwsA(isA<ValidationError>()));

    for (final destination in List.generate(255, (i) => i)) {
      Nonce(cookie, cs, 1, destination);
    }
  });

  test('toBytes', () {
    final cookieZero = Uint8List(Nonce.cookieLength);
    final cookieOne = Uint8List.fromList(List.filled(Nonce.cookieLength, 255));
    final csZero = CombinedSequence(Int64.ZERO);
    final csOne =
        CombinedSequence(CombinedSequence.combinedSequenceNumberMax - 1);

    expect(Nonce(cookieZero, csZero, 0, 0).toBytes().length, Nonce.totalLength);

    expect(Nonce(cookieZero, csZero, 0, 0).toBytes(), everyElement(equals(0)));
    expect(
        Nonce(cookieOne, csOne, 255, 255).toBytes(), everyElement(equals(255)));

    final alternate = Nonce(cookieOne, csZero, 0, 255).toBytes();
    // cookie
    expect(alternate.sublist(0, Nonce.cookieLength), everyElement(equals(255)));
    // source
    expect(alternate.sublist(Nonce.cookieLength, Nonce.cookieLength + 1), [0]);
    // destination
    expect(
      alternate.sublist(Nonce.cookieLength + 1, Nonce.cookieLength + 2),
      [255],
    );
    // combined sequence
    expect(alternate.sublist(Nonce.cookieLength + 2), everyElement(equals(0)));
  });

  test('fromBytes', () {
    final cookieZero = Uint8List(Nonce.cookieLength);
    final cookieOne = Uint8List.fromList(List.filled(Nonce.cookieLength, 255));
    final csZero = CombinedSequence(Int64.ZERO);
    final csOne =
        CombinedSequence(CombinedSequence.combinedSequenceNumberMax - 1);

    final nonces = [
      Nonce(cookieZero, csZero, 0, 0),
      Nonce(cookieOne, csOne, 255, 255),
      Nonce(cookieOne, csZero, 0, 255),
      Nonce(cookieZero, csOne, 255, 0),
    ];

    for (final nonce in nonces) {
      expect(Nonce.fromBytes(nonce.toBytes()), nonce);
    }
  });

  test('fromBytes too short', () {
    expect(() => Nonce.fromBytes(Uint8List(Nonce.totalLength - 1)),
        throwsA(isA<ValidationError>()));
  });
}
