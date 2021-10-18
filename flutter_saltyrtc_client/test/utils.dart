import 'dart:typed_data';

import 'package:dart_saltyrtc_client/dart_saltyrtc_client.dart'
    show Crypto, Event, TaskBuilder;
import 'package:flutter_saltyrtc_client/client.dart'
    show InitiatorClient, ResponderClient, SaltyRtcClient;
import 'package:hex/hex.dart';
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
  final Uint8List permanentPublicKey;

  Setup(this.client, this.name, this.authToken, this.permanentPublicKey);

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
  }) {
    final authTokenBytes = authToken ?? crypto.createAuthToken().bytes;
    final ourKeys = crypto.createKeyStore();
    final client = InitiatorClient.withUntrustedResponder(
      serverUri,
      ourKeys,
      tasks,
      pingInterval: pingInterval,
      expectedServerKey: expectedServerKey ?? serverPublicKey,
      sharedAuthToken: authTokenBytes,
    );
    return Setup(
        client, 'initiator(auth token)', authTokenBytes, ourKeys.publicKey);
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
    return Setup(client, 'responder(auth token)', authToken, ourKeys.publicKey);
  }

  Future<void> runAndTestEvents(List<void Function(Event)> testList) async {
    final events = client.run();
    final tests = testList.iterator;
    await for (final event in events.timeout(Duration(seconds: 10))) {
      if (!tests.moveNext()) {
        throw AssertionError('expected no further events but got: $event');
      }
      final test = tests.current;
      test(event);
    }
    if (tests.moveNext()) {
      throw AssertionError('expected more events');
    }
  }
}
