// Copyright 2021 Xayn AG
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:typed_data' show Uint8List;

import 'package:equatable/equatable.dart' show EquatableMixin;
import 'package:fixnum/fixnum.dart' show Int64;

/// The CombinedSequence class handles the overflow checking of the 48 bit combined sequence number
/// (CSN) consisting of the overflow number and the sequence number.
class CombinedSequence with EquatableMixin {
  static final Int64 combinedSequenceNumberMax = (Int64.ONE << 48) - 1;
  // define a mask 0xffff00000000 to select the overflow part
  static final Int64 _overflowMask = (Int64(1 << 16) - 1) << 32;
  static const numBytes = 6;

  /// Represent a 48bit combined sequence number.
  Int64 _combinedSequenceNumber;

  @override
  List<Object> get props => [_combinedSequenceNumber];

  CombinedSequence(this._combinedSequenceNumber) {
    if (_combinedSequenceNumber < 0 ||
        _combinedSequenceNumber > combinedSequenceNumberMax) {
      throw ArgumentError(
        'combined sequence number must be between 0 and 2**48-1',
      );
    }
  }

  factory CombinedSequence.fromRandom(Uint8List Function(int) randomBytes) {
    // we only want 32 bits random number, the top 16 must be set to 0.
    final sequenceNumber = randomBytes(4).buffer.asByteData().getUint32(0);
    return CombinedSequence(Int64.fromInts(0, sequenceNumber));
  }

  factory CombinedSequence.fromBytes(Uint8List bytes) {
    if (bytes.length != numBytes) {
      ArgumentError('buffer must contain 48 bit');
    }
    return CombinedSequence(
      Int64.fromBytesBigEndian(Uint8List(8)..setAll(2, bytes)),
    );
  }

  /// Creates a (deep) copy of this type.
  CombinedSequence copy() => CombinedSequence(_combinedSequenceNumber);

  bool get isOverflowZero =>
      _combinedSequenceNumber & _overflowMask == Int64.ZERO;

  /// Increase this sequence number by 1. Can throw exception if overflow.
  void next() {
    if (_combinedSequenceNumber + 1 > combinedSequenceNumberMax) {
      throw OverflowException();
    }

    _combinedSequenceNumber += 1;
  }

  Uint8List toBytes() {
    return Uint8List.fromList(
      _combinedSequenceNumber
          .toBytes()
          .reversed
          .skip(2)
          .toList(growable: false),
    );
  }
}

/// This means that the `overflow` field of `CombinedSequence` overflowed.
/// This must be treated as a protocol error.
class OverflowException implements Exception {}
