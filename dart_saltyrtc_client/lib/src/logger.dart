import 'package:logger/logger.dart'
    show Level, LogFilter, LogOutput, Logger, PrettyPrinter;

final _defaultLogger = Logger();
Logger? _logger;
Logger get logger => _logger ?? _defaultLogger;

/// Initializes a global logger.
void initLogger({
  int methodCount = 0,
  int errMethodCount = 5,
  Level? level,
  LogOutput? output,
  LogFilter? filter,
}) {
  _logger = Logger(
    printer: PrettyPrinter(
      printTime: true,
      printEmojis: true,
      colors: true,
      methodCount: methodCount,
      errorMethodCount: errMethodCount,
    ),
    level: level,
    output: output,
    filter: filter,
  );
}
