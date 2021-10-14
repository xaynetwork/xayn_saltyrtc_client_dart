library dart_saltyrtc_client;

import 'package:dart_saltyrtc_client/src/protocol/phases/server_handshake.dart'
    show saltyrtcSubprotocol;

export 'src/client.dart'
    show InitiatorClient, ResponderClient, SaltyRtcClientError;
export 'src/crypto/crypto.dart'
    show Crypto, KeyStore, SharedKeyStore, AuthToken, DecryptionFailedException;
export 'src/logger.dart' show initLogger;
// export all of events (all events, their variants, etc.)
export 'src/protocol/events.dart';
export 'src/protocol/network.dart'
    show WebSocket, WebSocketSink, WebSocketStream;
export 'src/protocol/task.dart' show Task, TaskBuilder;

const List<String> websocketProtocols = [saltyrtcSubprotocol];
