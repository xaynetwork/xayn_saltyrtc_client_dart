import 'package:test/test.dart';

void main() {
  // 1. setup tests like c2c handshake
  // 2. fake c2c handshake done
  // 3. do task phase tests
  test('start is called', () {}, skip: true);
  test('messages are forwarded', () {}, skip: true);
  test('events are forwarded', () {}, skip: true);
  group('cancel is called on', () {
    test('disconnect (initiator)', () {}, skip: true);
    test('disconnect (responder)', () {}, skip: true);
    test('send-error (initiator)', () {}, skip: true);
    test('send-error (responder)', () {}, skip: true);
    test('responder override', () {}, skip: true);
    test('initiator override', () {}, skip: true);
  });

  test('closing WS calls handleWSClosed ', () {}, skip: true);

  group('handover calls handleHandover when triggered by', () {
    test('link.handover()', () {}, skip: true);
    test('Close(Handover) msg', () {}, skip: true);
  });

  group('task exceptions in', () {
    test('start', () {}, skip: true);
    test('handleMessage', () {}, skip: true);
    test('handleEvent', () {}, skip: true);

    test('handleCancel', () {}, skip: true);

    test('handleWsClosed ', () {}, skip: true);

    test('handleHandover', () {}, skip: true);
  });
}
