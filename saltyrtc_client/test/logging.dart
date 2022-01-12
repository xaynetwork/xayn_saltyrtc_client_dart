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

import 'package:logger/logger.dart' show MemoryOutput, Logger, PrettyPrinter;
import 'package:test/test.dart' show setUp, tearDown, printOnFailure;
import 'package:xayn_saltyrtc_client/src/logger.dart' show initLogger;

/// Setup the logger to print logs only when a test fail.
void setUpLogging() {
  late MemoryOutput memoryOutput;

  setUp(() {
    memoryOutput = MemoryOutput();
    initLogger(
      Logger(
        printer: PrettyPrinter(),
        output: memoryOutput,
      ),
    );
  });

  tearDown(() async {
    for (final event in memoryOutput.buffer) {
      final output = event.lines.join('\n');
      printOnFailure(output);
    }
  });
}
