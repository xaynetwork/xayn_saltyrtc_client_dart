import 'dart:typed_data' show Uint8List;

import 'package:hex/hex.dart' show HEX;
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart'
    show WebSocketChannel;
import 'package:xayn_flutter_saltyrtc_client/events.dart'
    show IncompatibleServerKey, ServerHandshakeDone;
import 'package:xayn_flutter_saltyrtc_client/task.dart' show Pair;

import 'logging.dart' show setUpLogging;
import 'utils.dart' show Setup;

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

  if (await Setup.skipIntegrationTests()) {
    return;
  }

  group('Client server handshake', () {
    final initiatorSetup = Setup.initiatorWithAuthToken(tasks: []);
    final responderSetup = initiatorSetup.then(
      (initiatorSetup) => Setup.responderWithAuthToken(
        tasks: [],
        authToken: initiatorSetup.authToken!,
        initiatorTrustedKey: initiatorSetup.client.identity.getPublicKey(),
      ),
    );
    for (final data in [
      Pair('Initiator', initiatorSetup),
      Pair('Responder', responderSetup),
    ]) {
      test('Client ${data.first} server handshake', () async {
        final events = (await data.second).client.run();

        final serverHandshakeDone = await events.first;
        expect(serverHandshakeDone, isA<ServerHandshakeDone>());
      });
    }
  });

  group('Client server handhshake wrong server key,', () {
    final wrongServerKey = Uint8List.fromList(
      HEX.decode(
        '0000000000000000000000000000000000000000000000000000000000000001',
      ),
    );

    final initiatorSetup = Setup.initiatorWithAuthToken(
      tasks: [],
      expectedServerKey: wrongServerKey,
    );
    final responderSetup = initiatorSetup.then(
      (initiatorSetup) => Setup.responderWithAuthToken(
        tasks: [],
        authToken: initiatorSetup.authToken!,
        expectedServerKey: wrongServerKey,
        initiatorTrustedKey: initiatorSetup.client.identity.getPublicKey(),
      ),
    );
    for (final data in [
      Pair('Initiator', initiatorSetup),
      Pair('Responder', responderSetup)
    ]) {
      test('with a ${data.first} client', () async {
        final events = (await data.second).client.run();

        expect(
          () async {
            await events.first;
          },
          throwsA(isA<IncompatibleServerKey>()),
        );
      });
    }
  });
}
