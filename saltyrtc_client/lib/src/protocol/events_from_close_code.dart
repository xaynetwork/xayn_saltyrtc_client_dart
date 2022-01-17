// Copyright 2021 Xayn AG
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'package:meta/meta.dart' show protected;
import 'package:xayn_saltyrtc_client/events.dart'
    show
        Event,
        IncompatibleServerKey,
        InitiatorCouldNotDecrypt,
        LikelyTemporaryFailure,
        NoSharedTaskFound,
        TempFailureVariant,
        UnexpectedStatus,
        UnexpectedStatusVariant;
import 'package:xayn_saltyrtc_client/src/logger.dart' show logger;

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
        UnexpectedStatusVariant.protocolError,
        closeCode,
      );
    case 1006:
      return LikelyTemporaryFailure(TempFailureVariant.abnormalClosure);
    case 1009:
      return UnexpectedStatus.unchecked(
        UnexpectedStatusVariant.messageTooBig,
        closeCode,
      );
    case 1011:
    case 3002:
      return UnexpectedStatus.unchecked(
        UnexpectedStatusVariant.internalError,
        closeCode,
      );
    case 1012:
      return LikelyTemporaryFailure(TempFailureVariant.serviceRestart);
    case 1013:
      return LikelyTemporaryFailure(TempFailureVariant.tryAgainLater);
    case 1015:
      return UnexpectedStatus.unchecked(
        UnexpectedStatusVariant.tlsHandshake,
        closeCode,
      );
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
          UnexpectedStatusVariant.other,
          closeCode,
        );
      }
    default:
      return UnexpectedStatus.unchecked(
        UnexpectedStatusVariant.other,
        closeCode,
      );
  }
}
