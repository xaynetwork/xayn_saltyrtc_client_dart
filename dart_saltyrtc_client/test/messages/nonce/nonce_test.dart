import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/src/messages/id.dart' show Id;
import 'package:dart_saltyrtc_client/src/messages/nonce/combined_sequence.dart';
import 'package:dart_saltyrtc_client/src/messages/nonce/cookie.dart'
    show Cookie;
import 'package:dart_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;
import 'package:dart_saltyrtc_client/src/protocol/error.dart'
    show ValidationError;
import 'package:fixnum/fixnum.dart' show Int64;
import 'package:test/test.dart';

void main() {
  test('nonce length', () {
    expect(Nonce.totalLength, 24);
  });

  test('cookie length', () {
    expect(Cookie.cookieLength, 16);
  });

  test('valid cookie', () {
    final cs = CombinedSequence(Int64.ZERO);

    expect(
      () => Cookie(Uint8List(Cookie.cookieLength - 1)),
      throwsA(isA<ValidationError>()),
    );

    expect(
      () => Cookie(Uint8List(Cookie.cookieLength + 1)),
      throwsA(isA<ValidationError>()),
    );

    Nonce(
        Cookie(Uint8List(Cookie.cookieLength)), Id.peerId(1), Id.peerId(1), cs);
  });

  test('id valid source', () {
    final cs = CombinedSequence(Int64.ZERO);
    final cookie = Cookie(Uint8List(Cookie.cookieLength));

    expect(
      () => Nonce(cookie, Id.peerId(-1), Id.peerId(1), cs),
      throwsA(isA<ValidationError>()),
    );
    expect(
      () => Nonce(cookie, Id.peerId(256), Id.peerId(1), cs),
      throwsA(isA<ValidationError>()),
    );

    for (final source in List.generate(255, (i) => Id.peerId(i))) {
      Nonce(cookie, source, Id.peerId(1), cs);
    }
  });

  test('valid destination', () {
    final cs = CombinedSequence(Int64.ZERO);
    final cookie = Cookie(Uint8List(Cookie.cookieLength));

    expect(() => Nonce(cookie, Id.peerId(1), Id.peerId(-1), cs),
        throwsA(isA<ValidationError>()));
    expect(() => Nonce(cookie, Id.peerId(1), Id.peerId(256), cs),
        throwsA(isA<ValidationError>()));

    for (final destination in List.generate(255, (i) => Id.peerId(i))) {
      Nonce(cookie, Id.peerId(1), destination, cs);
    }
  });

  test('toBytes', () {
    final cookieZero = Cookie(Uint8List(Cookie.cookieLength));
    final cookieOne =
        Cookie(Uint8List.fromList(List.filled(Cookie.cookieLength, 255)));
    final csZero = CombinedSequence(Int64.ZERO);
    final csOne =
        CombinedSequence(CombinedSequence.combinedSequenceNumberMax - 1);

    expect(
        Nonce(cookieZero, Id.peerId(0), Id.peerId(0), csZero).toBytes().length,
        Nonce.totalLength);

    expect(Nonce(cookieZero, Id.peerId(0), Id.peerId(0), csZero).toBytes(),
        everyElement(equals(0)));
    expect(Nonce(cookieOne, Id.peerId(255), Id.peerId(255), csOne).toBytes(),
        everyElement(equals(255)));

    final alternate =
        Nonce(cookieOne, Id.peerId(0), Id.peerId(255), csZero).toBytes();
    // cookie
    expect(
        alternate.sublist(0, Cookie.cookieLength), everyElement(equals(255)));
    // source
    expect(
        alternate.sublist(Cookie.cookieLength, Cookie.cookieLength + 1), [0]);
    // destination
    expect(
      alternate.sublist(Cookie.cookieLength + 1, Cookie.cookieLength + 2),
      [255],
    );
    // combined sequence
    expect(alternate.sublist(Cookie.cookieLength + 2), everyElement(equals(0)));
  });

  test('fromBytes', () {
    final cookieZero = Cookie(Uint8List(Cookie.cookieLength));
    final cookieOne =
        Cookie(Uint8List.fromList(List.filled(Cookie.cookieLength, 255)));
    final csZero = CombinedSequence(Int64.ZERO);
    final csOne =
        CombinedSequence(CombinedSequence.combinedSequenceNumberMax - 1);

    final nonces = [
      Nonce(cookieZero, Id.peerId(0), Id.peerId(0), csZero),
      Nonce(cookieOne, Id.peerId(255), Id.peerId(255), csOne),
      Nonce(cookieOne, Id.peerId(0), Id.peerId(255), csZero),
      Nonce(cookieZero, Id.peerId(255), Id.peerId(0), csOne),
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
