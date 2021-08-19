import 'package:dart_saltyrtc_client/src/messages/id.dart' show Id;
import 'package:dart_saltyrtc_client/src/messages/validation.dart'
    show ValidationError;
import 'package:test/test.dart';

void main() {
  test('id valid peer', () {
    expect(
      () => Id.peerId(-1),
      throwsA(isA<ValidationError>()),
    );
    expect(
      () => Id.peerId(256),
      throwsA(isA<ValidationError>()),
    );

    for (final i in List.generate(255, (i) => i)) {
      Id.peerId(i);
    }
  });

  test('id valid client', () {
    expect(
      () => Id.clientId(0),
      throwsA(isA<ValidationError>()),
    );
    expect(
      () => Id.clientId(256),
      throwsA(isA<ValidationError>()),
    );

    for (final i in List.generate(254, (i) => i + 1)) {
      Id.clientId(i);
    }
  });

  test('id valid responder', () {
    expect(
      () => Id.responderId(1),
      throwsA(isA<ValidationError>()),
    );
    expect(
      () => Id.responderId(256),
      throwsA(isA<ValidationError>()),
    );

    for (final i in List.generate(253, (i) => i + 2)) {
      Id.responderId(i);
    }
  });
}