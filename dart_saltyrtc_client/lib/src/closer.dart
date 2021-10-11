import 'dart:async' show Completer, EventSink;

import 'package:dart_saltyrtc_client/src/logger.dart';
import 'package:dart_saltyrtc_client/src/messages/close_code.dart'
    show CloseCode, CloseCodeToFromInt;
import 'package:dart_saltyrtc_client/src/protocol/events.dart'
    show Event, InternalError, eventFromWSCloseCode;
import 'package:dart_saltyrtc_client/src/protocol/network.dart' show WebSocket;
import 'package:dart_saltyrtc_client/src/protocol/phases/phase.dart' show Phase;
import 'package:dart_saltyrtc_client/src/utils.dart' show EmitEventExt;
import 'package:meta/meta.dart' show protected;

/// Closing is a bit tricky as there are various places where we:
///
/// - do want to close from the inside
/// - do want to close from a task
/// - do want to close from the outside (e.g. canceling)
/// - realized we are closing (e.g. WS is closing)
/// - many of the think can happen in a async manner
///
/// If we do close depending on the phase and situation we are in we need
/// to do different actions.
///
/// Similar if we are closing we need to do different actions.
///
@protected
class Closer {
  bool _isClosing = false;
  bool _closedByUs = false;
  Phase? _currentPhase;

  /// Future which resolves when we are already in the process of closing.
  ///
  /// It's used to clean up thinks.
  final Completer<_CloseWith> _doCloseCompleter = Completer();

  // We could pass in a ClosingStatus { bool byUs, int? closeCode} in the future
  /// Future resolving when the client is more or less closed.
  final Completer<void> _closedCompleter = Completer();

  late Future<void> _onClosed;

  Closer(WebSocket webSocket, EventSink<Event> events) {
    // Running this code directly on the close() method call
    // is a bad idea as it's prone to lead to thinks like
    // "collection modified while iterating" problems etc.
    _doCloseCompleter.future.then((closeWith) {
      _closedByUs = true;
      final closeCode = closeWith.closeCode;
      final wasCanceled = closeWith.wasCanceled;
      logger.i(
          'Closing connection (closeCode=$closeCode, wasCanceled=$wasCanceled): ${closeWith.reason}');
      final phase = _currentPhase;
      int? wsCloseCode;
      if (phase != null) {
        // Give Phase a chance to send some remaining messages (e.g. `close`).
        // Also allow Phase to determine the closeCode/status used to close the
        // WebRtc Connection.
        try {
          wsCloseCode = phase.doClose(closeCode, wasCanceled);
        } catch (e, s) {
          events.emitEvent(InternalError(e), s);
          wsCloseCode = CloseCode.internalError.toInt();
        }
      } else {
        // Probably impossible, but it's better to be on the safe side and
        // make it not blow up due to some unrelated changes to the client.
        logger.w('close called before we started the SaltyRtc protocol');
        wsCloseCode = closeCode?.toInt();
      }
      // Only set it after calling `doClose`.
      _isClosing = true;
      webSocket.sink.close(wsCloseCode);
    }).onError((error, stackTrace) {
      events.emitEvent(InternalError(error ?? 'unknown error'), stackTrace);
    });

    _onClosed = _closedCompleter.future.whenComplete(() async {
      // If we get closed from WebRtc (instead of closing ourself), then
      // `_doCloseCompleter` is never completed and as such `_isClosing` was
      // never set.
      _isClosing = true;
      if (!_closedByUs) {
        final event = eventFromWSCloseCode(webSocket.closeCode);
        if (event != null) {
          events.emitEvent(event);
        }
      }
      events.close();
    });
  }

  /// Close the client.
  void close(CloseCode? closeCode, String? reason, {bool wasCanceled = false}) {
    _doCloseCompleter.complete(_CloseWith(closeCode, reason, wasCanceled));
  }

  /// Notify the closer that the connection is closed.
  void notifyConnectionClosed() {
    _closedCompleter.complete();
  }

  void setCurrentPhase(Phase current) {
    _currentPhase = current;
  }

  bool get isClosing => _isClosing;

  Future<void> get onClosed => _onClosed;
}

class _CloseWith {
  final CloseCode? closeCode;
  final String? reason;
  final bool wasCanceled;

  _CloseWith(this.closeCode, this.reason, this.wasCanceled);
}
