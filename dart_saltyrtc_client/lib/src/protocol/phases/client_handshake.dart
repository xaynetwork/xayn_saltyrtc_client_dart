import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/src/messages/id.dart' show Id;
import 'package:dart_saltyrtc_client/src/messages/message.dart' show Message;
import 'package:dart_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;
import 'package:dart_saltyrtc_client/src/messages/reader.dart'
    show MessageDecryptionExt;
import 'package:dart_saltyrtc_client/src/messages/s2c/disconnected.dart'
    show Disconnected;
import 'package:dart_saltyrtc_client/src/messages/s2c/new_initiator.dart';
import 'package:dart_saltyrtc_client/src/messages/s2c/new_responder.dart';
import 'package:dart_saltyrtc_client/src/messages/s2c/send_error.dart'
    show SendError;
import 'package:dart_saltyrtc_client/src/protocol/error.dart'
    show ProtocolError;
import 'package:dart_saltyrtc_client/src/protocol/phases/phase.dart' show Phase;
import 'package:dart_saltyrtc_client/src/protocol/phases/phase.dart';
import 'package:meta/meta.dart' show protected;

abstract class ClientHandshakePhase extends AfterServerHandshakePhase {
  final ClientHandshakeInput input;

  ClientHandshakePhase(CommonAfterServerHandshake common, this.input)
      : super(common);

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
    final msg = common.server.sessionSharedKey.readEncryptedMessage(
      msgBytes: msgBytes,
      nonce: nonce,
      debugHint: 'from server',
    );

    if (msg is SendError) {
      handleSendError(msg);
    } else if (msg is Disconnected) {
      handleDisconnected(msg);
    } else if (msg is NewResponder) {
      handleNewResponder(msg);
    } else if (msg is NewInitiator) {
      handleNewInitiator(msg);
    } else {
      handleUnexpectedMessage(msg);
    }

    return this;
  }

  void handleNewResponder(NewResponder msg) {
    handleUnexpectedMessage(msg);
  }

  void handleNewInitiator(NewInitiator msg) {
    handleUnexpectedMessage(msg);
  }

  void handleUnexpectedMessage(Message msg) {
    throw ProtocolError('Unexpected message of type ${msg.type}');
  }

  @protected
  Phase handleClientMessage(Uint8List msgBytes, Nonce nonce);
}
