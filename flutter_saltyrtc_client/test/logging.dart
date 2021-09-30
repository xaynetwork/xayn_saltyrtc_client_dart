import 'package:dart_saltyrtc_client/dart_saltyrtc_client.dart' show initLogger;
import 'package:logger/logger.dart' show MemoryOutput;
import 'package:test/test.dart' show setUp, tearDown, printOnFailure;

/// Setup the logger to print logs only when a test fail.
void setUpLogging() {
  late MemoryOutput memoryOutput;

  setUp(() {
    memoryOutput = MemoryOutput();
    initLogger(output: memoryOutput);
  });

  tearDown(() async {
    memoryOutput.buffer.forEach((event) {
      final output = event.lines.join('\n');
      printOnFailure(output);
    });
  });
}
