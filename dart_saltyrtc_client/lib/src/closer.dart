import 'dart:async' show Completer;

import 'package:dart_saltyrtc_client/src/logger.dart' show logger;
import 'package:dart_saltyrtc_client/src/messages/close_code.dart'
    show CloseCode, CloseCodeToFromInt;
import 'package:dart_saltyrtc_client/src/protocol/events.dart'
    show HandoverToTask, InternalError, eventFromWSCloseCode;
import 'package:dart_saltyrtc_client/src/protocol/network.dart' show WebSocket;
import 'package:dart_saltyrtc_client/src/protocol/phases/phase.dart' show Phase;
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

  // We could pass in a ClosingStatus { bool byUs, int? closeCode} in the future
  /// Future resolving when the client is more or less closed.
  final Completer<void> _closedCompleter = Completer();

  /// Creates a new closer.
  ///
  /// Be aware that [setCurrentPhase] *MUST* be called immediately after, i.e.
  /// it must be called in the same tick and micro task as the constructor.
  /// The only reason why we don't have it as an additional parameter is because
  /// it's a cyclic dependency.
  //TODO conider merging `Closer` and `Phase`, closer got much simpler since we
  //     made it.
  Closer(this._webSocket);

  /// Close the client.
  ///
  /// The will immediately call `doClose` on the current phase and close the
  /// `WebSocket` afterwards.
  ///
  /// This can be freely called from any async task.
  void close(CloseCode? closeCode, String? reason) {
    if (!_isClosing) {
      _isClosing = true;
      _closedByUs = true;
      logger.i('Closing connection (closeCode=$closeCode): $reason');
      int? wsCloseCode;
      // Give Phase a chance to send some remaining messages (e.g. `close`).
      // Also allow Phase to determine the closeCode/status used to close the
      // WebSocket Connection.
      try {
        wsCloseCode = _currentPhase!.doClose(closeCode);
      } catch (e, s) {
        _currentPhase!.emitEvent(InternalError(e), s);
        wsCloseCode = CloseCode.internalError.toInt();
      }
      _webSocket.sink.close(wsCloseCode);
    } else {
      logger.w('client closed more then once, ignoring: $closeCode, $reason');
    }
  }

  /// If when the WS stream closes this will not close the events interface,
  /// instead it will emit a [HandoverToTask] event.
  void enableHandover() {
    _doHandover = true;
  }

  /// Notify the closer that the connection is closed.
  void notifyConnectionClosed() {
    _isClosing = true;
    if (!_closedByUs) {
      final event = eventFromWSCloseCode(_webSocket.closeCode);
      if (event != null) {
        _currentPhase!.emitEvent(event);
      }
    }
    if (_doHandover) {
      _currentPhase!.emitEvent(HandoverToTask());
    } else {
      _currentPhase!.common.events.close();
    }
    _closedCompleter.complete();
  }

  void setCurrentPhase(Phase current) {
    _currentPhase = current;
  }

  bool get isClosing => _isClosing;

  /// Future resolving once the WebSocket stream is closed and we did
  /// close the events skink, and emitted a event based on the close code
  /// if necessary.
  Future<void> get onClosed => _closedCompleter.future;
}
