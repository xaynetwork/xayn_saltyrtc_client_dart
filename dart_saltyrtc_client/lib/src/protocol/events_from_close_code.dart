import 'package:dart_saltyrtc_client/events.dart'
    show
        Event,
        IncompatibleServerKey,
        InitiatorCouldNotDecrypt,
        LikelyTemporaryFailure,
        NoSharedTaskFound,
        TempFailureVariant,
        UnexpectedStatus,
        UnexpectedStatusVariant;
import 'package:dart_saltyrtc_client/src/logger.dart' show logger;
import 'package:meta/meta.dart' show protected;

/// Creates an event from an status code.
///
/// This should be used if the `WebSocket` was closed without us closing it,
/// to determine if we need to emit another event.
@protected
Event? eventFromWSCloseCode(int? closeCode, {bool codeFromClient = false}) {
  if (closeCode == null) {
    logger.e('unexpectedly received no closeCode');
    return UnexpectedStatus.unchecked(UnexpectedStatusVariant.other, closeCode);
  }
  switch (closeCode) {
    case 1000:
      return null;
    case 1002:
    case 1003:
    case 1007:
    case 3001:
      return UnexpectedStatus.unchecked(
          UnexpectedStatusVariant.protocolError, closeCode);
    case 1006:
      return LikelyTemporaryFailure(TempFailureVariant.abnormalClosure);
    case 1009:
      return UnexpectedStatus.unchecked(
          UnexpectedStatusVariant.messageTooBig, closeCode);
    case 1011:
    case 3002:
      return UnexpectedStatus.unchecked(
          UnexpectedStatusVariant.internalError, closeCode);
    case 1012:
      return LikelyTemporaryFailure(TempFailureVariant.serviceRestart);
    case 1013:
      return LikelyTemporaryFailure(TempFailureVariant.tryAgainLater);
    case 1015:
      return UnexpectedStatus.unchecked(
          UnexpectedStatusVariant.tlsHandshake, closeCode);
    case 3000:
      return LikelyTemporaryFailure(TempFailureVariant.pathFull);
    case 3004:
      return LikelyTemporaryFailure(TempFailureVariant.droppedByInitiator);
    case 3005:
      return InitiatorCouldNotDecrypt();
    case 3006:
      return NoSharedTaskFound();
    case 3007:
      return IncompatibleServerKey();
    case 3008:
      return LikelyTemporaryFailure(TempFailureVariant.timeout);
    case 3003:
      if (codeFromClient) {
        // Handover events are emitted differently (at a later point after
        // everything for the handover is setup).
        return null;
      } else {
        return UnexpectedStatus.unchecked(
            UnexpectedStatusVariant.other, closeCode);
      }
    default:
      return UnexpectedStatus.unchecked(
          UnexpectedStatusVariant.other, closeCode);
  }
}
