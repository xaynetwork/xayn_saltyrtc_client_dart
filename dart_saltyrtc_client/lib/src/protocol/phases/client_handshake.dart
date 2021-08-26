import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/src/messages/id.dart' show Id;
import 'package:dart_saltyrtc_client/src/messages/message.dart';
import 'package:dart_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;
import 'package:dart_saltyrtc_client/src/messages/reader.dart' show readMessage;
import 'package:dart_saltyrtc_client/src/messages/s2c/disconnected.dart';
import 'package:dart_saltyrtc_client/src/messages/s2c/send_error.dart'
    show SendError;
import 'package:dart_saltyrtc_client/src/protocol/error.dart'
    show ProtocolError, ensureNotNull;
import 'package:dart_saltyrtc_client/src/protocol/phases/phase.dart'
    show Phase, Common, ResponderPhase;
import 'package:dart_saltyrtc_client/src/protocol/phases/phase.dart';
import 'package:meta/meta.dart' show protected;

abstract class ClientHandshakePhase extends AfterServerHandshakePhase {
  ClientHandshakePhase(Common common) : super(common);

  @override
  Phase run(Uint8List msgBytes, Nonce nonce) {
    if (nonce.destination != common.address) {
      throw ProtocolError('Message destination does not match our address');
    }

    if (nonce.source == Id.serverAddress) {
      return _handleServerMessage(msgBytes, nonce);
    } else {
      return handleClientMessage(msgBytes, nonce);
    }
  }

  Phase _handleServerMessage(Uint8List msgBytes, Nonce nonce) {
    final msg = readMessage(ensureNotNull(common.server.sessionSharedKey)
        .decrypt(ciphertext: msgBytes, nonce: nonce.toBytes()));

    if (msg is SendError) {
      handleSendError(msg);
    } else if (msg is Disconnected) {
      handleDisconnected(msg);
    } else {
      handleServerMessageOther(msg, nonce);
    }

    return this;
  }

  @protected
  void handleServerMessageOther(Message msg, Nonce nonce);

  @protected
  Phase handleClientMessage(Uint8List msgBytes, Nonce nonce);
}

class ResponderClientHandshakePhase extends ClientHandshakePhase
    with ResponderPhase {
  @override
  final ResponderData data;

  ResponderClientHandshakePhase(Common common, this.data) : super(common);

  @override
  void handleServerMessageOther(Message msg, Nonce nonce) {
    throw UnimplementedError();
  }

  @override
  Phase handleClientMessage(Uint8List msgBytes, Nonce nonce) {
    throw UnimplementedError();
  }
}
