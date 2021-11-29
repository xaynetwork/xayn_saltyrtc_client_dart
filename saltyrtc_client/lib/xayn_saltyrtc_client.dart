library dart_saltyrtc_client;

import 'package:logger/logger.dart' show Logger;
import 'package:xayn_saltyrtc_client/src/logger.dart' show initLogger, logger;
import 'package:xayn_saltyrtc_client/src/protocol/phases/server_handshake.dart'
    show saltyrtcSubprotocol;

export 'package:xayn_saltyrtc_client/src/client.dart'
    show InitiatorClient, ResponderClient;
export 'package:xayn_saltyrtc_client/src/messages/c2c/task_message.dart'
    show TaskMessage;
export 'package:xayn_saltyrtc_client/src/messages/close_code.dart'
    show CloseCode;
export 'package:xayn_saltyrtc_client/src/messages/message.dart' show TaskData;
export 'package:xayn_saltyrtc_client/src/protocol/network.dart'
    show WebSocket, WebSocketSink, WebSocketStream;
export 'package:xayn_saltyrtc_client/src/protocol/task.dart'
    show Task, TaskBuilder, SaltyRtcTaskLink, CancelReason;
export 'package:xayn_saltyrtc_client/src/utils.dart' show Pair;

const List<String> websocketProtocols = [saltyrtcSubprotocol];

void saltyRtcClientLibInitLogger(Logger logger) => initLogger(logger);
Logger get saltyRtcClientLibLogger => logger;
