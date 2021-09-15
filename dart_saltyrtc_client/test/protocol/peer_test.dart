import 'package:test/test.dart';

void main() {
  test(
      'Responder.assertAuthenticated checks sessionSharedKey, permanentSharedKey, cookiePair, csPair',
      () {
    throw UnimplementedError();
  });

  test(
      'Initiator.assertAuthenticated checks sessionSharedKey, permanentSharedKey, cookiePair, csPair',
      () {
    throw UnimplementedError();
  });

  group('CookiePair.updateAndCheck', () {
    test('if their cookie is empty set it', () {
      throw UnimplementedError();
    });

    test("if their cookie is empty check they don't use our cookie", () {
      throw UnimplementedError();
    });

    test("if their cookie is known check if it's the same", () {
      throw UnimplementedError();
    });
  });

  group('CombinedSequencePair.updateAndCheck', () {
    test('if their CSN is empty set it', () {
      throw UnimplementedError();
    });

    test('if their CSN is empty check that overflow is 0', () {
      throw UnimplementedError();
    });

    test('if their CSN is known check if it was incremented by 1', () {
      throw UnimplementedError();
    });
  });
}
