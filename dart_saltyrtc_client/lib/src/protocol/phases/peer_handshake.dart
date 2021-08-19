import 'dart:typed_data';

import 'package:dart_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;
import 'package:dart_saltyrtc_client/src/protocol/phases/phase.dart'
    show Phase, Common;

class PeerHandshake<Data> extends Phase<Data> {
  PeerHandshake(Common common, Data data) : super(common, data);

  @override
  Phase run(Uint8List msgBytes, Nonce nonce) {
    // TODO: implement run
    throw UnimplementedError();
  }
}
