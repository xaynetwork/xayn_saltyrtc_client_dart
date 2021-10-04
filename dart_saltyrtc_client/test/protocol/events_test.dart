import 'package:dart_saltyrtc_client/src/protocol/events.dart'
    show
        IncompatibleServerKey,
        InitiatorCouldNotDecrypt,
        LikelyTemporaryFailure,
        NoSharedTaskFound,
        TempFailureVariant,
        UnexpectedStatus,
        UnexpectedStatusVariant,
        eventFromStatus;
import 'package:test/test.dart';

void main() {
  test('eventFromCloseCode', () {
    expect(eventFromStatus(1000), isNull);
    expect(eventFromStatus(1001), isNull);
    expect(
        eventFromStatus(1002),
        equals(UnexpectedStatus.unchecked(
            UnexpectedStatusVariant.protocolError, 1002)));
    expect(
        eventFromStatus(1003),
        equals(UnexpectedStatus.unchecked(
            UnexpectedStatusVariant.protocolError, 1003)));
    expect(
        eventFromStatus(1004),
        equals(
            UnexpectedStatus.unchecked(UnexpectedStatusVariant.other, 1004)));
    expect(
        eventFromStatus(1005),
        equals(
            UnexpectedStatus.unchecked(UnexpectedStatusVariant.other, 1005)));
    expect(eventFromStatus(1006),
        equals(LikelyTemporaryFailure(TempFailureVariant.abnormalClosure)));
    expect(
        eventFromStatus(1007),
        equals(UnexpectedStatus.unchecked(
            UnexpectedStatusVariant.protocolError, 1007)));
    expect(
        eventFromStatus(1008),
        equals(
            UnexpectedStatus.unchecked(UnexpectedStatusVariant.other, 1008)));
    expect(
        eventFromStatus(1009),
        equals(UnexpectedStatus.unchecked(
            UnexpectedStatusVariant.messageTooBig, 1009)));
    expect(
        eventFromStatus(1010),
        equals(
            UnexpectedStatus.unchecked(UnexpectedStatusVariant.other, 1010)));
    expect(
        eventFromStatus(1011),
        equals(UnexpectedStatus.unchecked(
            UnexpectedStatusVariant.internalError, 1011)));
    expect(eventFromStatus(1012),
        equals(LikelyTemporaryFailure(TempFailureVariant.serviceRestart)));
    expect(eventFromStatus(1013),
        equals(LikelyTemporaryFailure(TempFailureVariant.tryAgainLater)));
    expect(
        eventFromStatus(1014),
        equals(
            UnexpectedStatus.unchecked(UnexpectedStatusVariant.other, 1014)));
    expect(
        eventFromStatus(1015),
        equals(UnexpectedStatus.unchecked(
            UnexpectedStatusVariant.tlsHandshake, 1015)));
    expect(eventFromStatus(3000),
        equals(LikelyTemporaryFailure(TempFailureVariant.pathFull)));
    expect(
        eventFromStatus(3001),
        equals(UnexpectedStatus.unchecked(
            UnexpectedStatusVariant.protocolError, 3001)));
    expect(
        eventFromStatus(3002),
        equals(UnexpectedStatus.unchecked(
            UnexpectedStatusVariant.internalError, 3002)));
    expect(
        eventFromStatus(3003),
        equals(
            UnexpectedStatus.unchecked(UnexpectedStatusVariant.other, 3003)));
    expect(eventFromStatus(3004),
        equals(LikelyTemporaryFailure(TempFailureVariant.droppedByInitiator)));
    expect(eventFromStatus(3005), equals(InitiatorCouldNotDecrypt()));
    expect(eventFromStatus(3006), equals(NoSharedTaskFound()));
    expect(eventFromStatus(3007), equals(IncompatibleServerKey()));
    expect(eventFromStatus(3008),
        equals(LikelyTemporaryFailure(TempFailureVariant.timeout)));

    expect(
        eventFromStatus(3009),
        equals(
            UnexpectedStatus.unchecked(UnexpectedStatusVariant.other, 3009)));
    expect(
        eventFromStatus(1016),
        equals(
            UnexpectedStatus.unchecked(UnexpectedStatusVariant.other, 1016)));
  });
}
