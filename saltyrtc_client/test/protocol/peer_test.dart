import 'package:fixnum/fixnum.dart' show Int64;
import 'package:test/test.dart';
import 'package:xayn_saltyrtc_client/src/messages/id.dart' show Id;
import 'package:xayn_saltyrtc_client/src/messages/nonce/combined_sequence.dart'
    show CombinedSequence;
import 'package:xayn_saltyrtc_client/src/messages/nonce/cookie.dart'
    show Cookie;
import 'package:xayn_saltyrtc_client/src/protocol/peer.dart'
    show
        AuthenticatedInitiator,
        AuthenticatedResponder,
        CombinedSequencePair,
        CookiePair,
        Initiator,
        Responder;

import '../crypto_mock.dart' show crypto;
import '../utils.dart' show setUpTesting, throwsValidationError;

void main() {
  setUpTesting();

  final key1 = crypto.createKeyStore();
  final key2 = crypto.createKeyStore();
  final key3 = crypto.createKeyStore();
  final sharedKey1f2 = crypto.createSharedKeyStore(
    ownKeyStore: key1,
    remotePublicKey: key2.publicKey,
  );
  final sharedKey1f3 = crypto.createSharedKeyStore(
    ownKeyStore: key1,
    remotePublicKey: key3.publicKey,
  );
  final responderId1 = Id.responderId(23);
  final initiatorId = Id.initiatorAddress;
  final cookie = Cookie.fromRandom(crypto.randomBytes);

  CombinedSequence mkCSN() => CombinedSequence.fromRandom(crypto.randomBytes);

  group('Responder.assertAuthenticated', () {
    test('creates an AuthenticatedResponder', () {
      final responder = Responder(responderId1, crypto);
      responder.setPermanentSharedKey(sharedKey1f2);
      responder.setSessionSharedKey(sharedKey1f3);
      responder.cookiePair.updateAndCheck(cookie, initiatorId);
      responder.csPair.updateAndCheck(mkCSN(), initiatorId);
      expect(responder.assertAuthenticated(), isA<AuthenticatedResponder>());
    });

    test('check sessionSharedKey', () {
      final responder = Responder(responderId1, crypto);
      responder.setPermanentSharedKey(sharedKey1f2);
      responder.cookiePair.updateAndCheck(cookie, initiatorId);
      responder.csPair.updateAndCheck(mkCSN(), initiatorId);
      expect(() => responder.assertAuthenticated(), throwsStateError);
    });

    test('check permanentSharedKey', () {
      final responder = Responder(Id.responderId(23), crypto);
      responder.setSessionSharedKey(sharedKey1f3);
      responder.cookiePair.updateAndCheck(cookie, initiatorId);
      responder.csPair.updateAndCheck(mkCSN(), initiatorId);
      expect(() => responder.assertAuthenticated(), throwsStateError);
    });

    test('check cookiePair', () {
      final responder = Responder(Id.responderId(23), crypto);
      responder.setPermanentSharedKey(sharedKey1f2);
      responder.setSessionSharedKey(sharedKey1f3);
      responder.csPair.updateAndCheck(mkCSN(), initiatorId);
      expect(() => responder.assertAuthenticated(), throwsStateError);
    });

    test('check csPair', () {
      final responder = Responder(Id.responderId(23), crypto);
      responder.setPermanentSharedKey(sharedKey1f2);
      responder.setSessionSharedKey(sharedKey1f3);
      responder.cookiePair.updateAndCheck(cookie, initiatorId);
      expect(() => responder.assertAuthenticated(), throwsStateError);
    });
  });

  group('Initiator.assertAuthenticated', () {
    test('creates an AuthenticatedInitiator', () {
      final initiator = Initiator(crypto);
      initiator.setPermanentSharedKey(sharedKey1f2);
      initiator.setSessionSharedKey(sharedKey1f3);
      initiator.cookiePair.updateAndCheck(cookie, responderId1);
      initiator.csPair.updateAndCheck(mkCSN(), responderId1);
      expect(initiator.assertAuthenticated(), isA<AuthenticatedInitiator>());
    });

    test('check sessionSharedKey', () {
      final initiator = Initiator(crypto);
      initiator.setPermanentSharedKey(sharedKey1f2);
      initiator.cookiePair.updateAndCheck(cookie, responderId1);
      initiator.csPair.updateAndCheck(mkCSN(), responderId1);
      expect(() => initiator.assertAuthenticated(), throwsStateError);
    });

    test('check permanentSharedKey', () {
      final initiator = Initiator(crypto);
      initiator.setSessionSharedKey(sharedKey1f3);
      initiator.cookiePair.updateAndCheck(cookie, responderId1);
      initiator.csPair.updateAndCheck(mkCSN(), responderId1);
      expect(() => initiator.assertAuthenticated(), throwsStateError);
    });

    test('check cookiePair', () {
      final initiator = Initiator(crypto);
      initiator.setPermanentSharedKey(sharedKey1f2);
      initiator.setSessionSharedKey(sharedKey1f3);
      initiator.csPair.updateAndCheck(mkCSN(), responderId1);
      expect(() => initiator.assertAuthenticated(), throwsStateError);
    });

    test('check csPair', () {
      final initiator = Initiator(crypto);
      initiator.setPermanentSharedKey(sharedKey1f2);
      initiator.setSessionSharedKey(sharedKey1f3);
      initiator.cookiePair.updateAndCheck(cookie, responderId1);
      expect(() => initiator.assertAuthenticated(), throwsStateError);
    });
  });

  group('CookiePair.updateAndCheck', () {
    CookiePair mkPair() {
      final pair = CookiePair.fromRandom(crypto);
      expect(pair.theirs, isNull);
      return pair;
    }

    test('if their cookie is empty set it', () {
      final pair = mkPair();
      pair.updateAndCheck(cookie, responderId1);
      expect(pair.theirs, equals(cookie));
    });

    test("if their cookie is empty check they don't use our cookie", () {
      final pair = mkPair();
      expect(
        () {
          pair.updateAndCheck(pair.ours, responderId1);
        },
        throwsValidationError(),
      );
    });

    test("if their cookie is known check if it's the same", () {
      final pair = mkPair();
      pair.updateAndCheck(cookie, responderId1);
      expect(
        () {
          pair.updateAndCheck(pair.ours, responderId1);
        },
        throwsValidationError(),
      );
    });
  });

  group('CombinedSequencePair.updateAndCheck', () {
    CombinedSequencePair mkPair() {
      final pair = CombinedSequencePair.fromRandom(crypto);
      expect(pair.theirs, isNull);
      return pair;
    }

    test('if their CSN is empty set it', () {
      final pair = mkPair();
      final csn = CombinedSequence.fromRandom(crypto.randomBytes);
      pair.updateAndCheck(csn, responderId1);
      expect(pair.theirs, equals(csn));
    });

    test('if their CSN is empty check that overflow is 0', () {
      final pair = mkPair();
      final csn = CombinedSequence(Int64(0x100000000));
      expect(csn.isOverflowZero, isFalse);
      expect(
        () => pair.updateAndCheck(csn, responderId1),
        throwsValidationError(),
      );
    });

    test('if their CSN is known check if it was incremented by 1', () {
      final pair = mkPair();
      final csn = CombinedSequence.fromRandom(crypto.randomBytes);
      pair.updateAndCheck(csn, responderId1);
      expect(pair.theirs, equals(csn));
      csn.next();
      pair.updateAndCheck(csn, responderId1);
      expect(pair.theirs, equals(csn));
      csn.next();
      csn.next();
      expect(
        () => pair.updateAndCheck(csn, responderId1),
        throwsValidationError(),
      );
    });
  });
}
