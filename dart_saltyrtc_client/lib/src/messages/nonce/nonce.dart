import 'dart:typed_data' show Uint8List, BytesBuilder;

import 'package:dart_saltyrtc_client/src/messages/nonce/combined_sequence.dart'
    show CombinedSequence;
import 'package:dart_saltyrtc_client/src/messages/validation.dart'
    show ValidationError, validateId;
import 'package:equatable/equatable.dart' show EquatableMixin;
import 'package:meta/meta.dart' show immutable;

/// Nonce structure:
/// |CCCCCCCCCCCCCCCC|S|D|OO|QQQQ|
///
/// - C: Cookie (16 byte)
/// - S: Source byte (1 byte)
/// - D: Destination byte (1 byte)
/// - O: Overflow number (2 byte)
/// - Q: Sequence number (4 byte)
/// we threat overflow and sequence as one 48bit number (combined sequence number)
@immutable
class Nonce with EquatableMixin {
  static const cookieLength = 16;
  static const totalLength = 24;

  final Uint8List cookie;
  final int source;
  final int destination;
  final CombinedSequence combinedSequence;

  @override
  List<Object> get props => [source, destination, combinedSequence, cookie];

  Nonce(this.cookie, this.combinedSequence, this.source, this.destination) {
    if (cookie.length != cookieLength) {
      throw ValidationError('cookie must be $cookieLength bytes long');
    }
    validateId(source, 'source');
    validateId(destination, 'destination');
  }

  factory Nonce.fromBytes(Uint8List bytes) {
    if (bytes.length < totalLength) {
      throw ValidationError('buffer limit must be at least $totalLength');
    }

    final cookie = bytes.sublist(0, cookieLength);
    final source = bytes[cookieLength];
    final destination = bytes[cookieLength + 1];
    final combinedSequence = CombinedSequence.fromBytes(bytes.sublist(
        cookieLength + 2, cookieLength + 2 + CombinedSequence.numBytes));

    return Nonce(cookie, combinedSequence, source, destination);
  }

  Uint8List toBytes() {
    final builder = BytesBuilder(copy: false);
    builder.add(cookie);
    builder.addByte(source);
    builder.addByte(destination);
    builder.add(combinedSequence.toBytes());

    return builder.toBytes();
  }
}
