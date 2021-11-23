import 'package:logger/logger.dart' show MemoryOutput;
import 'package:test/test.dart' show setUp, tearDown, printOnFailure;
import 'package:xayn_saltyrtc_client/xayn_saltyrtc_client.dart' show initLogger;

/// Setup the logger to print logs only when a test fail.
void setUpLogging() {
  late MemoryOutput memoryOutput;

  setUp(() {
    memoryOutput = MemoryOutput();
    initLogger(output: memoryOutput);
  });

  tearDown(() async {
    for (final event in memoryOutput.buffer) {
      final output = event.lines.join('\n');
      printOnFailure(output);
    }
  });
}
