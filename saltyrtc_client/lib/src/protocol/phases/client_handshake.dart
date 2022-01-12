// Copyright 2021 Xayn AG
//
// Licensed under the Apache License, Version 2.0 (the License);
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:typed_data' show Uint8List;

import 'package:meta/meta.dart' show protected;
import 'package:xayn_saltyrtc_client/src/logger.dart' show logger;
import 'package:xayn_saltyrtc_client/src/messages/id.dart' show Id;
import 'package:xayn_saltyrtc_client/src/messages/message.dart' show Message;
import 'package:xayn_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;
import 'package:xayn_saltyrtc_client/src/messages/reader.dart'
    show MessageDecryptionExt;
import 'package:xayn_saltyrtc_client/src/messages/s2c/disconnected.dart'
    show Disconnected;
import 'package:xayn_saltyrtc_client/src/messages/s2c/new_initiator.dart'
    show NewInitiator;
import 'package:xayn_saltyrtc_client/src/messages/s2c/new_responder.dart'
    show NewResponder;
import 'package:xayn_saltyrtc_client/src/messages/s2c/send_error.dart'
    show SendError;
import 'package:xayn_saltyrtc_client/src/protocol/error.dart'
    show ProtocolErrorException;
import 'package:xayn_saltyrtc_client/src/protocol/peer.dart' show Peer;
import 'package:xayn_saltyrtc_client/src/protocol/phases/phase.dart'
    show AfterServerHandshakePhase, AfterServerHandshakeCommon, Phase;

abstract class ClientHandshakePhase extends AfterServerHandshakePhase {
  ClientHandshakePhase(AfterServerHandshakeCommon common) : super(common);

  @override
  Phase run(Peer source, Uint8List msgBytes, Nonce nonce) {
    if (nonce.destination != common.address) {
      throw const ProtocolErrorException(
        'Message destination does not match our address',
      );
    }
    logger.v('message from ${nonce.destination}');

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
    throw ProtocolErrorException('Unexpected message of type ${msg.type}');
  }

  @protected
  Phase handleClientMessage(Uint8List msgBytes, Nonce nonce);
}
