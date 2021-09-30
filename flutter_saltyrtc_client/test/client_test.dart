import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/dart_saltyrtc_client.dart'
    show ServerHandshakeDone;
import 'package:flutter_saltyrtc_client/client.dart'
    show InitiatorClient, ResponderClient;
import 'package:flutter_saltyrtc_client/crypto/crypto_provider.dart'
    show getCrypto;
import 'package:flutter_saltyrtc_client/flutter_saltyrtc_client.dart';
import 'package:hex/hex.dart' show HEX;
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart'
    show WebSocketChannel;

import 'logging.dart' show setUpLogging;

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

void main() async {
  setUpLogging();

  final serverUri = Uri.parse('ws://localhost:8765');
  final serverPublicKey = Uint8List.fromList(
    HEX.decode(
        '09a59a5fa6b45cb07638a3a6e347ce563a948b756fd22f9527465f7c79c2a864'),
  );
  const pingInterval = 60;
  final crypto = await getCrypto();

  if (!await isServerActive(serverUri)) {
    print('W: Server is down, no integration test will be performed');
    return;
  }

  test('Client initiator server handshake', () async {
    final ourPermanentKeys = crypto.createKeyStore();

    final client = InitiatorClient.withUntrustedResponder(
      serverUri,
      ourPermanentKeys,
      [],
      expectedServerKey: serverPublicKey,
      pingInterval: pingInterval,
      sharedAuthToken: crypto.createAuthToken().bytes,
    );

    client.run();

    final serverHandshakeDone = await client.events.first;
    expect(serverHandshakeDone, isA<ServerHandshakeDone>());
  });

  test('Client responder server handshake', () async {
    final ourPermanentKeys = crypto.createKeyStore();
    final initiatorTrustedKey = crypto.createKeyStore().publicKey;

    final client = ResponderClient.withTrustedKey(
      serverUri,
      ourPermanentKeys,
      [],
      pingInterval: pingInterval,
      expectedServerKey: serverPublicKey,
      initiatorTrustedKey: initiatorTrustedKey,
    );

    client.run();

    final serverHandshakeDone = await client.events.first;
    expect(serverHandshakeDone, isA<ServerHandshakeDone>());
  });
}
