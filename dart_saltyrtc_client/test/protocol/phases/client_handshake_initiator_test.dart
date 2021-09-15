import 'package:test/test.dart';

void main() {
  group('successful transition', () {
    test('initial(expect token) -> key', () {
      throw UnimplementedError();
    });

    test('initial(expect key) -> auth', () {
      throw UnimplementedError();
    });

    test('key -> auth', () {
      throw UnimplementedError();
    });

    test('auth -> next phase', () {
      throw UnimplementedError();
    });
  });

  group('auth/decryption failure', () {
    test('initial(expect token) -> drop', () {
      throw UnimplementedError();
    });
    test('initial(expect key) -> drop', () {
      throw UnimplementedError();
    });
    test('key -> drop', () {
      throw UnimplementedError();
    });

    test('auth -> protocol error', () {
      throw UnimplementedError();
    });
  });

  test('auth -> no task found', () {
    throw UnimplementedError();
  });
}
