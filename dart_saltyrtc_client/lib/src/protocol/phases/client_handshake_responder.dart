import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/src/messages/message.dart' show Message;
import 'package:dart_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;
import 'package:dart_saltyrtc_client/src/protocol/peer.dart'
    show AuthenticatedServer;
import 'package:dart_saltyrtc_client/src/protocol/phases/client_handshake.dart'
    show ClientHandshakePhase;
import 'package:dart_saltyrtc_client/src/protocol/phases/phase.dart'
    show ResponderPhase, ResponderData, Common, Phase, ClientHandshakeInput;

class ResponderClientHandshakePhase extends ClientHandshakePhase
    with ResponderPhase {
  @override
  final ResponderData data;

  ResponderClientHandshakePhase(Common common, ClientHandshakeInput input,
      AuthenticatedServer authServer, this.data)
      : super(common, authServer, input);

  @override
  void handleServerMessageOther(Message msg, Nonce nonce) {
    throw UnimplementedError();
  }

  @override
  Phase handleClientMessage(Uint8List msgBytes, Nonce nonce) {
    throw UnimplementedError();
  }
}
