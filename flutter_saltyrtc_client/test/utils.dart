import 'dart:collection' show Queue;
import 'dart:typed_data' show Uint8List;

import 'package:hex/hex.dart' show HEX;
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart'
    show WebSocketChannel;
import 'package:xayn_flutter_saltyrtc_client/events.dart' show Event;
import 'package:xayn_flutter_saltyrtc_client/src/client.dart'
    show Identity, InitiatorClient, ResponderClient, SaltyRtcClient;
import 'package:xayn_saltyrtc_client/xayn_saltyrtc_client.dart'
    show TaskBuilder;

Future<bool> isServerActive(Uri uri) async {
  try {
    final ws = WebSocketChannel.connect(uri);
    // needed to really connect to the server
    await ws.stream.isEmpty;
  } catch (e) {
    return Future.value(false);
  }
  return Future.value(true);
}

class Setup {
  static const int pingInterval = 60;
  static final serverUri = Uri.parse('ws://localhost:8765');
  static final serverPublicKey = Uint8List.fromList(
    HEX.decode(
      '09a59a5fa6b45cb07638a3a6e347ce563a948b756fd22f9527465f7c79c2a864',
    ),
  );

  final SaltyRtcClient client;
  final Uint8List? authToken;

  Setup(this.client, this.authToken);

  static Future<bool> skipIntegrationTests() async {
    if (!await isServerActive(serverUri)) {
      print('W: Server is down, no integration test will be performed');
      return true;
    }
    return false;
  }

  static Future<Setup> initiatorWithAuthToken({
    required List<TaskBuilder> tasks,
    Uint8List? expectedServerKey,
    Uint8List? authToken,
    Identity? identity,
  }) async {
    final authTokenBytes = authToken ?? await InitiatorClient.createAuthToken();
    final client = await InitiatorClient.withUntrustedResponder(
      serverUri,
      tasks,
      pingInterval: pingInterval,
      expectedServerKey: expectedServerKey ?? serverPublicKey,
      sharedAuthToken: authTokenBytes,
      identity: identity,
    );
    return Setup(client, authTokenBytes);
  }

  static Future<Setup> responderWithAuthToken({
    required List<TaskBuilder> tasks,
    required Uint8List authToken,
    required Uint8List initiatorTrustedKey,
    Uint8List? expectedServerKey,
    Identity? identity,
  }) async {
    final client = await ResponderClient.withAuthToken(
      serverUri,
      tasks,
      pingInterval: pingInterval,
      expectedServerKey: expectedServerKey ?? serverPublicKey,
      initiatorTrustedKey: initiatorTrustedKey,
      sharedAuthToken: authToken,
    );
    return Setup(client, authToken);
  }

  Future<void> runAndTestEvents(List<void Function(Event)> testList) async {
    final errors = Queue<Event>();
    final events =
        client.run().timeout(const Duration(seconds: 10)).handleError(
      (Object? o) {
        errors.add(o as Event);
      },
      test: (Object? o) => o is Event,
    );
    final tests = testList.iterator;

    await for (final event in events) {
      if (!tests.moveNext()) {
        throw AssertionError('expected no further events but got: $event');
      }
      tests.current(event);
    }
    while (tests.moveNext()) {
      expect(errors, isNotEmpty);
      tests.current(errors.removeFirst());
    }
    expect(errors, isEmpty);
  }
}
