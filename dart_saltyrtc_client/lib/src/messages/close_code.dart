import 'package:dart_saltyrtc_client/src/messages/validation.dart'
    show ValidationError;
import 'package:quiver/collection.dart' show HashBiMap;

enum CloseCode {
  /// Normal closing of websocket.
  closingNormal,

  /// The endpoint is going away.
  goingAway,

  /// No shared sub-protocol could be found.
  noSharedSubprotocol,

  /// No free responder byte.
  pathFull,

  /// Invalid message, invalid path length, ...
  protocolError,

  /// Syntax error, ...
  internalError,

  /// Handover of the signaling channel.
  handover,

  /// Dropped by initator.
  /// For an initiator, that means that another initiator has connected to the path.
  /// For a responder, it means that an initiator requested to drop the responder.
  droppedByInitiator,

  /// Initiator could not decrypt a message.
  initiatorCouldNotDecrypt,

  /// No shared task was found.
  noSharedTask,

  /// Invalid key.
  invalidKey,

  /// Timeout.
  timeout,
}

HashBiMap<CloseCode, int> _closeCode2IntBiMap() {
  final map = HashBiMap<CloseCode, int>();

  map.addAll({
    CloseCode.closingNormal: 1000,
    CloseCode.goingAway: 1001,
    CloseCode.noSharedSubprotocol: 1002,
    CloseCode.pathFull: 3000,
    CloseCode.protocolError: 3001,
    CloseCode.internalError: 3002,
    CloseCode.handover: 3003,
    CloseCode.droppedByInitiator: 3004,
    CloseCode.initiatorCouldNotDecrypt: 3005,
    CloseCode.noSharedTask: 3006,
    CloseCode.invalidKey: 3007,
    CloseCode.timeout: 3008,
  });

  return map;
}

final _cc2int = _closeCode2IntBiMap();

extension CloseCodeToFromInt on CloseCode {
  int toInt() {
    // _cc2int must contain all CloseCode variants
    return _cc2int[this]!;
  }

  static CloseCode fromInt(int value) {
    final cc = _cc2int.inverse[value];
    if (cc == null) {
      throw ValidationError('$value is not a valid close code');
    }
    return cc;
  }
}

const List<CloseCode> closeCodesAll = CloseCode.values;