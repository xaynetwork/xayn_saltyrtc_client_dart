import 'dart:typed_data' show Uint8List, BytesBuilder;

import 'package:dart_saltyrtc_client/src/messages/id.dart' show Id;
import 'package:dart_saltyrtc_client/src/messages/nonce/combined_sequence.dart'
    show CombinedSequence;
import 'package:dart_saltyrtc_client/src/messages/nonce/cookie.dart'
    show Cookie;
import 'package:dart_saltyrtc_client/src/messages/validation.dart'
    show ValidationError;
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
/// we treat overflow and sequence as one 48bit number (combined sequence number)
@immutable
class Nonce with EquatableMixin {
  static const totalLength = 24;

  final Cookie cookie;
  final Id source;
  final Id destination;
  final CombinedSequence combinedSequence;

  @override
  List<Object> get props => [cookie, source, destination, combinedSequence];

  Nonce(
    this.cookie,
    this.source,
    this.destination,
    this.combinedSequence,
  );

  factory Nonce.fromBytes(Uint8List bytes) {
    if (bytes.length < totalLength) {
      throw ValidationError('buffer limit must be at least $totalLength');
    }

    final cookie = bytes.sublist(0, Cookie.cookieLength);
    final source = Id.peerId(bytes[Cookie.cookieLength]);
    final destination = Id.peerId(bytes[Cookie.cookieLength + 1]);
    final combinedSequence = CombinedSequence.fromBytes(bytes.sublist(
        Cookie.cookieLength + 2,
        Cookie.cookieLength + 2 + CombinedSequence.numBytes));

    return Nonce(Cookie(cookie), source, destination, combinedSequence);
  }

  Uint8List toBytes() {
    final builder = BytesBuilder(copy: false);
    builder.add(cookie.toBytes());
    builder.addByte(source.value);
    builder.addByte(destination.value);
    builder.add(combinedSequence.toBytes());

    return builder.toBytes();
  }
}
