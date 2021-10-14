import 'dart:async' show Completer, EventSink;

import 'package:dart_saltyrtc_client/src/logger.dart' show logger;
import 'package:dart_saltyrtc_client/src/messages/close_code.dart'
    show CloseCode, CloseCodeToFromInt;
import 'package:dart_saltyrtc_client/src/protocol/events.dart'
    show Event, HandoverToTask, InternalError, eventFromWSCloseCode;
import 'package:dart_saltyrtc_client/src/protocol/network.dart' show WebSocket;
import 'package:dart_saltyrtc_client/src/protocol/phases/phase.dart' show Phase;
import 'package:dart_saltyrtc_client/src/utils.dart' show EmitEventExt;
import 'package:meta/meta.dart' show protected;

/// Closing is a bit tricky as there are various places where we:
///
/// - do want to close from the inside
/// - do want to close from a task
/// - do want to close from the outside
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
  bool _doHandover = false;

  final WebSocket _webSocket;
  final EventSink<Event> _events;

  // We could pass in a ClosingStatus { bool byUs, int? closeCode} in the future
  /// Future resolving when the client is more or less closed.
  final Completer<void> _closedCompleter = Completer();

  /// Future resolving once the WebSocket stream is closed and we did
  /// close the events skink, and emitted a event based on the close code
  /// if necessary.
  late Future<void> _onClosed;

  Closer(this._webSocket, this._events) {
    _onClosed = _closedCompleter.future.whenComplete(() async {
      _isClosing = true;
      if (!_closedByUs) {
        final event = eventFromWSCloseCode(_webSocket.closeCode);
        if (event != null) {
          _events.emitEvent(event);
        }
      }
      if (!_doHandover) {
        _events.close();
      }
    });
  }

  /// Close the client.
  ///
  /// The will immediately call `doClose` on the current phase and close the
  /// `WebSocket` afterwards.
  void close(CloseCode? closeCode, String? reason) {
    if (!_isClosing) {
      _isClosing = true;
      _closedByUs = true;
      logger.i('Closing connection (closeCode=$closeCode): $reason');
      final phase = _currentPhase;
      int? wsCloseCode;
      if (phase != null) {
        // Give Phase a chance to send some remaining messages (e.g. `close`).
        // Also allow Phase to determine the closeCode/status used to close the
        // WebSocket Connection.
        try {
          wsCloseCode = phase.doClose(closeCode);
        } catch (e, s) {
          _events.emitEvent(InternalError(e), s);
          wsCloseCode = CloseCode.internalError.toInt();
        }
      } else {
        logger.w('close called before we started the SaltyRtc protocol');
        wsCloseCode = closeCode?.toInt();
      }
      _webSocket.sink.close(wsCloseCode);
    } else {
      logger.w('client closed more then once, ignoring: $closeCode, $reason');
    }
  }

  /// Closes the WebSocket for a task handover.
  ///
  /// This will prevent `events` from being closed when the
  /// `WebSocket` is closed.
  void handover() {
    _doHandover = true;
    close(CloseCode.handover, 'handover');
    _events.emitEvent(HandoverToTask());
  }

  /// Notify the closer that the connection is closed.
  void notifyConnectionClosed() {
    _isClosing = true;
    _closedCompleter.complete();
  }

  void setCurrentPhase(Phase current) {
    _currentPhase = current;
  }

  bool get isClosing => _isClosing;

  Future<void> get onClosed => _onClosed;
}
