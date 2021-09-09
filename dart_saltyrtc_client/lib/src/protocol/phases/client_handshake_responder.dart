import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;
import 'package:dart_saltyrtc_client/src/messages/s2c/new_initiator.dart'
    show NewInitiator;
import 'package:dart_saltyrtc_client/src/protocol/phases/client_handshake.dart'
    show ClientHandshakePhase;
import 'package:dart_saltyrtc_client/src/protocol/phases/phase.dart'
    show
        ResponderPhase,
        ResponderData,
        CommonAfterServerHandshake,
        Phase,
        ClientHandshakeInput;

class ResponderClientHandshakePhase extends ClientHandshakePhase
    with ResponderPhase {
  @override
  final ResponderData data;

  ResponderClientHandshakePhase(
    CommonAfterServerHandshake common,
    ClientHandshakeInput input,
    this.data,
  ) : super(common, input);

  @override
  Phase handleClientMessage(Uint8List msgBytes, Nonce nonce) {
    // TODO: implement handleClientMessage
    throw UnimplementedError();
  }

  @override
  void handleNewInitiator(NewInitiator msg) {
    throw UnimplementedError();
  }
}
