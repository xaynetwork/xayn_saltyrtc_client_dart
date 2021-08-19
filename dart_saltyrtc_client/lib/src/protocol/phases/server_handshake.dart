import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/src/messages/id.dart' show Id;
import 'package:dart_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;
import 'package:dart_saltyrtc_client/src/messages/validation.dart'
    show ValidationError, validateIdResponder;
import 'package:dart_saltyrtc_client/src/protocol/phases/phase.dart'
    show Phase, Common;
import 'package:dart_saltyrtc_client/src/protocol/role.dart' show Role;

enum ServerHandshakeState { start, helloSent, authSent, done }

class ServerHandshake<Data> extends Phase<Data> {
  ServerHandshakeState _handshakeState = ServerHandshakeState.start;

  ServerHandshake(Common common, Data data) : super(common, data);

  @override
  void validateNonceSource(Nonce nonce) {
    final source = nonce.source;
    if (source != Id.serverAddress) {
      throw ValidationError(
          'Received message is not from server. Found $source', false);
    }
  }

  @override
  void validateNonceDestination(Nonce nonce) {
    final destination = nonce.destination;
    final check = (Id expected) {
      if (destination != expected) {
        throw ValidationError(
          'Receive message with invalid nonce destination. '
          'Expected $expected, found $destination',
        );
      }
    };

    switch (_handshakeState) {
      // the address is still unknown
      case ServerHandshakeState.start:
      case ServerHandshakeState.helloSent:
        check(Id.unknowAddress);
        return;
      // if we are a:
      // - initiator destination must be Id.initiatorAddress
      // - responder destination must be between 2 and 255
      case ServerHandshakeState.authSent:
        if (common.role == Role.initiator) {
          check(Id.initiatorAddress);
        } else {
          validateIdResponder(destination.value, 'nonce destination');
        }
        return;
      // server handshake is done so we can use the general implementation
      case ServerHandshakeState.done:
        super.validateNonceDestination(nonce);
    }
  }

  @override
  Phase run(Uint8List msgBytes, Nonce nonce) {
    // TODO: implement run
    throw UnimplementedError();
  }
}
