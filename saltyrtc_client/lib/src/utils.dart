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

import 'dart:async' show EventSink;

import 'package:xayn_saltyrtc_client/events.dart' show Event, ClosingErrorEvent;

import 'package:xayn_saltyrtc_client/src/logger.dart' show logger;

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
