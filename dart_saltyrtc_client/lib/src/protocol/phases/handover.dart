import 'dart:typed_data';

import 'package:dart_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;
import 'package:dart_saltyrtc_client/src/protocol/phases/phase.dart'
    show Phase, Common;

abstract class HandoverPhase extends Phase {
  HandoverPhase(Common common) : super(common);

  @override
  Phase run(Uint8List msgBytes, Nonce nonce) {
    // TODO: implement run
    throw UnimplementedError();
  }
}
