import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/src/messages/id.dart' show Id;
import 'package:dart_saltyrtc_client/src/messages/message.dart' show Message;
import 'package:dart_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;
import 'package:dart_saltyrtc_client/src/messages/reader.dart'
    show MessageDecryptionExt;
import 'package:dart_saltyrtc_client/src/messages/s2c/disconnected.dart'
    show Disconnected;
import 'package:dart_saltyrtc_client/src/messages/s2c/new_initiator.dart'
    show NewInitiator;
import 'package:dart_saltyrtc_client/src/messages/s2c/new_responder.dart'
    show NewResponder;
import 'package:dart_saltyrtc_client/src/messages/s2c/send_error.dart'
    show SendError;
import 'package:dart_saltyrtc_client/src/protocol/error.dart'
    show ProtocolException;
import 'package:dart_saltyrtc_client/src/protocol/peer.dart' show Peer;
import 'package:dart_saltyrtc_client/src/protocol/phases/phase.dart'
    show AfterServerHandshakePhase, AfterServerHandshakeCommon, Phase;
import 'package:meta/meta.dart' show protected;

abstract class ClientHandshakePhase extends AfterServerHandshakePhase {
  ClientHandshakePhase(AfterServerHandshakeCommon common) : super(common);

  @override
  Phase run(Peer source, Uint8List msgBytes, Nonce nonce) {
    if (nonce.destination != common.address) {
      throw ProtocolException('Message destination does not match our address');
    }

    if (nonce.source == Id.serverAddress) {
      return _handleServerMessage(msgBytes, nonce);
    } else {
      return handleClientMessage(msgBytes, nonce);
    }
  }

  Phase _handleServerMessage(Uint8List msgBytes, Nonce nonce) {
    final msg = common.server.sessionSharedKey.readEncryptedMessage(
      msgBytes: msgBytes,
      nonce: nonce,
    );

    if (msg is SendError) {
      return handleSendError(msg);
    } else if (msg is Disconnected) {
      return handleDisconnected(msg);
    } else if (msg is NewResponder) {
      return handleNewResponder(msg);
    } else if (msg is NewInitiator) {
      return handleNewInitiator(msg);
    } else {
      return handleUnexpectedMessage(msg);
    }
  }

  Phase handleNewResponder(NewResponder msg) => handleUnexpectedMessage(msg);

  Phase handleNewInitiator(NewInitiator msg) => handleUnexpectedMessage(msg);

  Phase handleUnexpectedMessage(Message msg) {
    throw ProtocolException('Unexpected message of type ${msg.type}');
  }

  @protected
  Phase handleClientMessage(Uint8List msgBytes, Nonce nonce);
}
