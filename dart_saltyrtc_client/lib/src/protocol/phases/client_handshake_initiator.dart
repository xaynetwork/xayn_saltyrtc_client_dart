import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/src/messages/message.dart' show Message;
import 'package:dart_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;
import 'package:dart_saltyrtc_client/src/protocol/phases/client_handshake.dart'
    show ClientHandshakePhase;
import 'package:dart_saltyrtc_client/src/protocol/phases/phase.dart'
    show InitiatorPhase, InitiatorData, Common, Phase, ClientHandshakeInput;

class InitiatorClientHandshakePhase extends ClientHandshakePhase
    with InitiatorPhase {
  @override
  final InitiatorData data;

  InitiatorClientHandshakePhase(
      Common common, ClientHandshakeInput input, this.data)
      : super(common, input);

  @override
  void handleServerMessageOther(Message msg, Nonce nonce) {
    throw UnimplementedError();
  }

  @override
  Phase handleClientMessage(Uint8List msgBytes, Nonce nonce) {
    throw UnimplementedError();
  }
}
