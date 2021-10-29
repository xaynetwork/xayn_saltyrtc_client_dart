import 'dart:collection' show Queue;
import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/dart_saltyrtc_client.dart'
    show Crypto, Event, KeyStore, TaskBuilder;
import 'package:flutter_saltyrtc_client/client.dart'
    show InitiatorClient, ResponderClient, SaltyRtcClient;
import 'package:hex/hex.dart' show HEX;
import 'package:test/expect.dart';
import 'package:web_socket_channel/web_socket_channel.dart'
    show WebSocketChannel;

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
        '09a59a5fa6b45cb07638a3a6e347ce563a948b756fd22f9527465f7c79c2a864'),
  );

  final SaltyRtcClient client;
  final String name;
  final Uint8List? authToken;
  final KeyStore permanentKey;

  Setup(this.client, this.name, this.authToken, this.permanentKey);

  static Future<void> serverReady() async {
    if (!await isServerActive(serverUri)) {
      print('W: Server is down, no integration test will be performed');
      return;
    }
  }

  factory Setup.initiatorWithAuthToken(
    Crypto crypto, {
    required List<TaskBuilder> tasks,
    Uint8List? expectedServerKey,
    Uint8List? authToken,
    KeyStore? privateKey,
  }) {
    final authTokenBytes = authToken ?? crypto.createAuthToken().bytes;
    final ourKey = privateKey ?? crypto.createKeyStore();
    final client = InitiatorClient.withUntrustedResponder(
      serverUri,
      ourKey,
      tasks,
      pingInterval: pingInterval,
      expectedServerKey: expectedServerKey ?? serverPublicKey,
      sharedAuthToken: authTokenBytes,
    );
    return Setup(client, 'initiator(auth token)', authTokenBytes, ourKey);
  }

  factory Setup.responderWithAuthToken(
    Crypto crypto, {
    required List<TaskBuilder> tasks,
    Uint8List? expectedServerKey,
    required Uint8List authToken,
    required Uint8List initiatorTrustedKey,
  }) {
    final ourKeys = crypto.createKeyStore();
    final client = ResponderClient.withAuthToken(
      serverUri,
      ourKeys,
      tasks,
      pingInterval: pingInterval,
      expectedServerKey: expectedServerKey ?? serverPublicKey,
      initiatorTrustedKey: initiatorTrustedKey,
      sharedAuthToken: authToken,
    );
    return Setup(client, 'responder(auth token)', authToken, ourKeys);
  }

  Future<void> runAndTestEvents(List<void Function(Event)> testList) async {
    final errors = Queue<Event>();
    final events = client.run().timeout(Duration(seconds: 10)).handleError(
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
