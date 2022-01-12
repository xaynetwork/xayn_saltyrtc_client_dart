// Copyright 2021 Xayn AG
//
// Licensed under the Apache License, Version 2.0 (the License);
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'package:test/test.dart';
import 'package:xayn_saltyrtc_client/src/messages/id.dart' show Id;
import 'package:xayn_saltyrtc_client/src/protocol/error.dart'
    show ValidationException;

void main() {
  test('id valid peer', () {
    expect(
      () => Id.peerId(-1),
      throwsA(isA<ValidationException>()),
    );
    expect(
      () => Id.peerId(256),
      throwsA(isA<ValidationException>()),
    );

    for (final i in List.generate(255, (i) => i)) {
      Id.peerId(i);
    }
  });

  test('id valid client', () {
    expect(
      () => Id.clientId(0),
      throwsA(isA<ValidationException>()),
    );
    expect(
      () => Id.clientId(256),
      throwsA(isA<ValidationException>()),
    );

    for (final i in List.generate(254, (i) => i + 1)) {
      Id.clientId(i);
    }
  });

  test('id valid responder', () {
    expect(
      () => Id.responderId(1),
      throwsA(isA<ValidationException>()),
    );
    expect(
      () => Id.responderId(256),
      throwsA(isA<ValidationException>()),
    );

    for (final i in List.generate(253, (i) => i + 2)) {
      Id.responderId(i);
    }
  });
}
