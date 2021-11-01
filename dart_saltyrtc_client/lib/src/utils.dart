import 'dart:async' show EventSink;

import 'package:dart_saltyrtc_client/events.dart' show Event, ClosingErrorEvent;

import 'logger.dart' show logger;

/// Pair of two values.
class Pair<T1, T2> {
  final T1 first;
  final T2 second;
  Pair(this.first, this.second);
}

extension EmitEventExt on EventSink<Event> {
  void emitEvent(Event event, [StackTrace? stackTrace]) {
    try {
      if (event is ClosingErrorEvent) {
        addError(event, stackTrace ?? StackTrace.current);
      } else {
        add(event);
      }
    } on StateError catch (e) {
      if (!e.toString().contains('closed')) {
        rethrow;
      }
      // Ignore events emitted after the event stream was closed
      // this can happen easily with for example error events.
      logger.d('event after events closed: $e');
    }
  }
}
