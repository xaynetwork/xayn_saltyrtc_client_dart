import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/dart_saltyrtc_client.dart'
    show IncompatibleServerKey, ServerHandshakeDone;
import 'package:flutter_saltyrtc_client/client.dart'
    show InitiatorClient, ResponderClient, SaltyRtcClient;
import 'package:flutter_saltyrtc_client/crypto/crypto_provider.dart'
    show getCrypto;
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

class Setup {
  final SaltyRtcClient client;
  final String name;

  Setup(this.client, this.name);
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

  Setup initiatorWithUntrustedResponder({Uint8List? expectedServerKey}) {
    return Setup(
      InitiatorClient.withUntrustedResponder(
        serverUri,
        crypto.createKeyStore(),
        [],
        expectedServerKey: expectedServerKey ?? serverPublicKey,
        pingInterval: pingInterval,
        sharedAuthToken: crypto.createAuthToken().bytes,
      ),
      'initiator(untrusted responder)',
    );
  }

  Setup responderWithTrustedKey({Uint8List? expectedServerKey}) {
    return Setup(
      ResponderClient.withTrustedKey(
        serverUri,
        crypto.createKeyStore(),
        [],
        pingInterval: pingInterval,
        expectedServerKey: expectedServerKey ?? serverPublicKey,
        initiatorTrustedKey: crypto.createKeyStore().publicKey,
      ),
      'responder(with trusted key)',
    );
  }

  group(
    'Client server handhshake',
    () {
      for (final data in [
        initiatorWithUntrustedResponder(),
        responderWithTrustedKey()
      ]) {
        test('Client ${data.name} server handshake', () async {
          final events = data.client.run();

          final serverHandshakeDone = await events.first;
          expect(serverHandshakeDone, isA<ServerHandshakeDone>());
        });
      }
    },
  );

  group('Client server handhshake wrong server key,', () {
    final wrongServerKey = Uint8List.fromList(
      HEX.decode(
          '0000000000000000000000000000000000000000000000000000000000000001'),
    );

    for (final data in [
      initiatorWithUntrustedResponder(expectedServerKey: wrongServerKey),
      responderWithTrustedKey(expectedServerKey: wrongServerKey),
    ]) {
      test('with a ${data.name} client', () async {
        final events = data.client.run();

        expect(() async {
          await events.first;
        }, throwsA(isA<IncompatibleServerKey>()));
      });
    }
  });
}
