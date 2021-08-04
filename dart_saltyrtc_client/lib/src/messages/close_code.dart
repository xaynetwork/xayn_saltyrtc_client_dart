// TODO can we remove the class?
class CloseCode {
  CloseCode._();

  /// Normal closing of websocket.
  static const closingNormal = 1000;

  /// The endpoint si going away.
  static const goingAway = 1001;

  /// No shared sub-protocol could be found.
  static const noSharedSubprotocol = 1002;

  /// No free responder byte.
  static const pathFull = 3000;

  /// Invalid message, invalid path length, ...
  static const protocolError = 3001;

  /// Syntax error, ...
  static const internalError = 3002;

  /// Handover of the signaling channel.
  static const handover = 3003;

  /// Dropped by initator.
  /// For an initiator, that means that another initiator has connected to the path.
  /// For a responder, it means that an initiator requested to drop the responder.
  static const droppedByInitiator = 3004;

  /// Initiator could not dectypt a message.
  static const initiatorCouldNotDecrypt = 3005;

  /// No shared task was found.
  static const noSharedTask = 3006;

  /// Invalid key.
  static const invalidKey = 3007;

  /// Timeout.
  static const timeout = 3008;

  static const closeCodesDropResponder = [
    protocolError,
    internalError,
    droppedByInitiator,
    initiatorCouldNotDecrypt,
  ];

  static const closeCodesAll = [
    closingNormal,
    goingAway,
    noSharedTask,
    pathFull,
    protocolError,
    internalError,
    handover,
    droppedByInitiator,
    initiatorCouldNotDecrypt,
    noSharedTask,
    invalidKey,
    timeout
  ];
}
