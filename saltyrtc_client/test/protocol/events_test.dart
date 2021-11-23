import 'package:test/test.dart';
import 'package:xayn_saltyrtc_client/events.dart'
    show
        IncompatibleServerKey,
        InitiatorCouldNotDecrypt,
        LikelyTemporaryFailure,
        NoSharedTaskFound,
        TempFailureVariant,
        UnexpectedStatus,
        UnexpectedStatusVariant;
import 'package:xayn_saltyrtc_client/src/protocol/events_from_close_code.dart'
    show eventFromWSCloseCode;

void main() {
  test('eventFromCloseCode', () {
    expect(eventFromWSCloseCode(1000), isNull);
    expect(
        eventFromWSCloseCode(1001),
        equals(
            UnexpectedStatus.unchecked(UnexpectedStatusVariant.other, 1001)));
    expect(
        eventFromWSCloseCode(1002),
        equals(UnexpectedStatus.unchecked(
            UnexpectedStatusVariant.protocolError, 1002)));
    expect(
        eventFromWSCloseCode(1003),
        equals(UnexpectedStatus.unchecked(
            UnexpectedStatusVariant.protocolError, 1003)));
    expect(
        eventFromWSCloseCode(1004),
        equals(
            UnexpectedStatus.unchecked(UnexpectedStatusVariant.other, 1004)));
    expect(
        eventFromWSCloseCode(1005),
        equals(
            UnexpectedStatus.unchecked(UnexpectedStatusVariant.other, 1005)));
    expect(eventFromWSCloseCode(1006),
        equals(LikelyTemporaryFailure(TempFailureVariant.abnormalClosure)));
    expect(
        eventFromWSCloseCode(1007),
        equals(UnexpectedStatus.unchecked(
            UnexpectedStatusVariant.protocolError, 1007)));
    expect(
        eventFromWSCloseCode(1008),
        equals(
            UnexpectedStatus.unchecked(UnexpectedStatusVariant.other, 1008)));
    expect(
        eventFromWSCloseCode(1009),
        equals(UnexpectedStatus.unchecked(
            UnexpectedStatusVariant.messageTooBig, 1009)));
    expect(
        eventFromWSCloseCode(1010),
        equals(
            UnexpectedStatus.unchecked(UnexpectedStatusVariant.other, 1010)));
    expect(
        eventFromWSCloseCode(1011),
        equals(UnexpectedStatus.unchecked(
            UnexpectedStatusVariant.internalError, 1011)));
    expect(eventFromWSCloseCode(1012),
        equals(LikelyTemporaryFailure(TempFailureVariant.serviceRestart)));
    expect(eventFromWSCloseCode(1013),
        equals(LikelyTemporaryFailure(TempFailureVariant.tryAgainLater)));
    expect(
        eventFromWSCloseCode(1014),
        equals(
            UnexpectedStatus.unchecked(UnexpectedStatusVariant.other, 1014)));
    expect(
        eventFromWSCloseCode(1015),
        equals(UnexpectedStatus.unchecked(
            UnexpectedStatusVariant.tlsHandshake, 1015)));
    expect(eventFromWSCloseCode(3000),
        equals(LikelyTemporaryFailure(TempFailureVariant.pathFull)));
    expect(
        eventFromWSCloseCode(3001),
        equals(UnexpectedStatus.unchecked(
            UnexpectedStatusVariant.protocolError, 3001)));
    expect(
        eventFromWSCloseCode(3002),
        equals(UnexpectedStatus.unchecked(
            UnexpectedStatusVariant.internalError, 3002)));
    expect(eventFromWSCloseCode(3004),
        equals(LikelyTemporaryFailure(TempFailureVariant.droppedByInitiator)));
    expect(eventFromWSCloseCode(3005), equals(InitiatorCouldNotDecrypt()));
    expect(eventFromWSCloseCode(3006), equals(NoSharedTaskFound()));
    expect(eventFromWSCloseCode(3007), equals(IncompatibleServerKey()));
    expect(eventFromWSCloseCode(3008),
        equals(LikelyTemporaryFailure(TempFailureVariant.timeout)));

    expect(
        eventFromWSCloseCode(3009),
        equals(
            UnexpectedStatus.unchecked(UnexpectedStatusVariant.other, 3009)));
    expect(
        eventFromWSCloseCode(1016),
        equals(
            UnexpectedStatus.unchecked(UnexpectedStatusVariant.other, 1016)));
  });
}
