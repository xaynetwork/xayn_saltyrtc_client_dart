import 'dart:async' show EventSink;

import 'package:dart_saltyrtc_client/src/protocol/events.dart'
    show Event, ClosingErrorEvent;

/// Pair of two values.
class Pair<T1, T2> {
  final T1 first;
  final T2 second;
  Pair(this.first, this.second);
}

extension EmitEventExt on EventSink<Event> {
  void emitEvent(Event event, [StackTrace? stackTrace]) {
    if (event is ClosingErrorEvent) {
      addError(event, stackTrace ?? StackTrace.current);
    } else {
      add(event);
    }
  }
}
