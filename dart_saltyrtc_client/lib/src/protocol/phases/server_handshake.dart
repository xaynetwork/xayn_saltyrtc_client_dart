import 'dart:typed_data' show Uint8List, BytesBuilder;

import 'package:collection/collection.dart' show ListEquality;
import 'package:dart_saltyrtc_client/src/logger.dart' show logger;
import 'package:dart_saltyrtc_client/src/messages/id.dart' show Id;
import 'package:dart_saltyrtc_client/src/messages/message.dart'
    show MessageType, Message, MessageFields;
import 'package:dart_saltyrtc_client/src/messages/nonce/cookie.dart'
    show Cookie;
import 'package:dart_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;
import 'package:dart_saltyrtc_client/src/messages/reader.dart'
    show MessageDecryptionExt, readMessage;
import 'package:dart_saltyrtc_client/src/messages/s2c/client_auth.dart'
    show ClientAuth;
import 'package:dart_saltyrtc_client/src/messages/s2c/client_hello.dart'
    show ClientHello;
import 'package:dart_saltyrtc_client/src/messages/s2c/server_auth_initiator.dart'
    show ServerAuthInitiator;
import 'package:dart_saltyrtc_client/src/messages/s2c/server_auth_responder.dart'
    show ServerAuthResponder;
import 'package:dart_saltyrtc_client/src/messages/s2c/server_hello.dart'
    show ServerHello;
import 'package:dart_saltyrtc_client/src/messages/validation.dart'
    show validateIdResponder;
import 'package:dart_saltyrtc_client/src/protocol/error.dart'
    show ProtocolError, ValidationError, ensureNotNull;
import 'package:dart_saltyrtc_client/src/protocol/peer.dart' show Peer;
import 'package:dart_saltyrtc_client/src/protocol/phases/client_handshake_initiator.dart'
    show InitiatorClientHandshakePhase;
import 'package:dart_saltyrtc_client/src/protocol/phases/client_handshake_responder.dart'
    show ResponderClientHandshakePhase;
import 'package:dart_saltyrtc_client/src/protocol/phases/phase.dart'
    show
        Common,
        CommonAfterServerHandshake,
        Phase,
        InitiatorIdentity,
        ResponderData,
        ResponderPhase,
        ClientHandshakeInput;
import 'package:dart_saltyrtc_client/src/protocol/role.dart' show Role;
import 'package:meta/meta.dart' show protected;

const saltyrtcSubprotocol = 'v1.saltyrtc.org';

enum ServerHandshakeState { start, helloSent, authSent }

/// In this phase the client and server will exchange cryptographic keys.
/// Messages flow:
///
///     +--------------+     +-------------+
/// --->+ server-hello |  +->+ client-auth |
///     +------+-------+  |  +------+------+
///            |          |         |
///            v          |         v
///     +------+-------+  |  +------+------+
///     | client-hello +--+  | server-auth |
///     +--------------+     +------+------+
///
/// client-hello is only sent by the responder.
abstract class ServerHandshakePhase extends Phase {
  ServerHandshakeState handshakeState = ServerHandshakeState.start;

  // data that is needed by the client handshake phase
  final ClientHandshakeInput clientHandshakeInput;
  final int _pingInterval;

  ServerHandshakePhase(
      Common common, this.clientHandshakeInput, this._pingInterval)
      : super(common);

  @protected
  Phase handleServerAuth(Message msg, Nonce nonce);

  @protected
  void sendClientHello();

  @override
  void validateNonceSource(Nonce nonce) {
    final source = nonce.source;
    if (source != Id.serverAddress) {
      throw ValidationError(
        'Received message is not from server. Found $source',
        isProtocolError: false,
      );
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

    switch (handshakeState) {
      // the address is still unknown
      case ServerHandshakeState.start:
      case ServerHandshakeState.helloSent:
        check(Id.unknownAddress);
        return;
      // if we are a:
      // - initiator destination must be Id.initiatorAddress
      // - responder destination must be between 2 and 255
      case ServerHandshakeState.authSent:
        if (role == Role.initiator) {
          check(Id.initiatorAddress);
        } else {
          validateIdResponder(destination.value, 'nonce destination');
        }
        return;
    }
  }

  @override
  Peer getPeerWithId(Id id) {
    if (id.isServer()) return common.server;
    throw ProtocolError('Invalid peer id: $id');
  }

  @override
  Phase run(Uint8List msgBytes, Nonce nonce) {
    // the first message is not encrypted
    final Message msg;
    if (handshakeState == ServerHandshakeState.start) {
      msg = readMessage(msgBytes);
    } else {
      msg = ensureNotNull(common.server.sessionSharedKey).readEncryptedMessage(
        msgBytes: msgBytes,
        nonce: nonce,
        debugHint: 'from server',
      );
    }

    switch (handshakeState) {
      case ServerHandshakeState.start:
        {
          if (msg is ServerHello) {
            handleServerHello(msg, nonce);
            sendClientHello();
            sendClientAuth();
          } else {
            throw ProtocolError(
                'Expected ${MessageType.serverHello}, but got ${msg.type}');
          }
          logger.v('Current server handshake status $handshakeState');
        }
        return this;
      case ServerHandshakeState.helloSent:
        throw ProtocolError(
            'Received ${msg.type} message before sending ${MessageType.clientAuth}');
      case ServerHandshakeState.authSent:
        return handleServerAuth(msg, nonce);
    }
  }

  void handleServerHello(ServerHello msg, Nonce nonce) {
    final sks = common.crypto.createSharedKeyStore(
        ownKeyStore: common.ourKeys, remotePublicKey: msg.key);
    common.server.setSessionSharedKey(sks);
  }

  void sendClientAuth() {
    final serverCookie = ensureNotNull(common.server.cookiePair.theirs);
    final subprotocols = [saltyrtcSubprotocol];
    sendMessage(
      ClientAuth(
        serverCookie,
        common.expectedServerKey,
        subprotocols,
        _pingInterval,
      ),
      to: common.server,
    );
    handshakeState = ServerHandshakeState.authSent;
  }

  /// Validate the signed keys sent by the server.
  void validateSignedKey({
    required Uint8List? signedKey,
    required Nonce nonce,
    required Uint8List? expectedServerKey,
  }) {
    if (expectedServerKey == null) return;

    if (signedKey == null) {
      throw ValidationError(
          'Server did not send ${MessageFields.signedKeys} in ${MessageType.serverAuth} message');
    }

    final sks = ensureNotNull(common.server.sessionSharedKey);
    final decrypted = common.ourKeys.decrypt(
        remotePublicKey: expectedServerKey,
        ciphertext: signedKey,
        nonce: nonce.toBytes());
    final expected = BytesBuilder(copy: false)
      ..add(sks.remotePublicKey)
      ..add(common.ourKeys.publicKey);
    if (!ListEquality<int>().equals(decrypted, expected.takeBytes())) {
      throw ValidationError(
          'Decrypted ${MessageFields.signedKeys} in ${MessageType.serverAuth} message is invalid');
    }
  }

  void validateRepeatedCookie(Cookie cookie) {
    if (cookie != common.server.cookiePair.ours) {
      throw ProtocolError(
          'Bad repeated cookie in ${MessageType.serverAuth} message');
    }
  }
}

class InitiatorServerHandshakePhase extends ServerHandshakePhase
    with InitiatorIdentity {
  InitiatorServerHandshakePhase(
    Common common,
    ClientHandshakeInput clientHandshakeInput,
    int pingInterval,
  ) : super(common, clientHandshakeInput, pingInterval);

  @override
  void sendClientHello() {
    // noop as an initiator
  }

  @override
  Phase handleServerAuth(Message msg, Nonce nonce) {
    logger.d('Initiator server handshake handling server-auth');

    if (msg is! ServerAuthInitiator) {
      throw ProtocolError('Message is not ${MessageType.serverAuth}');
    }

    if (!nonce.destination.isInitiator()) {
      throw ValidationError('Invalid none destination ${nonce.destination}');
    }

    common.address = Id.initiatorAddress;

    validateRepeatedCookie(msg.yourCookie);

    validateSignedKey(
        signedKey: msg.signedKeys,
        nonce: nonce,
        expectedServerKey: common.expectedServerKey);

    logger.d('Switching to initiator client handshake');
    final nextPhase = InitiatorClientHandshakePhase(
      CommonAfterServerHandshake(common),
      clientHandshakeInput,
    );
    msg.responders.forEach(nextPhase.addNewResponder);
    return nextPhase;
  }
}

class ResponderServerHandshakePhase extends ServerHandshakePhase
    with ResponderPhase {
  @override
  final ResponderData data;

  ResponderServerHandshakePhase(Common common,
      ClientHandshakeInput clientHandshakeInput, int pingInterval, this.data)
      : super(common, clientHandshakeInput, pingInterval);

  @override
  void sendClientHello() {
    logger.d('Switching to responder client handshake');
    sendMessage(ClientHello(common.ourKeys.publicKey),
        to: common.server, encrypted: false);
    handshakeState = ServerHandshakeState.helloSent;
  }

  @override
  Phase handleServerAuth(Message msg, Nonce nonce) {
    if (msg is! ServerAuthResponder) {
      throw ProtocolError('Message is not ${MessageType.serverAuth}');
    }

    if (!nonce.destination.isResponder()) {
      throw ValidationError('Invalid none destination ${nonce.destination}');
    }

    // this is our address from the server
    common.address = nonce.destination;

    validateRepeatedCookie(msg.yourCookie);

    validateSignedKey(
        signedKey: msg.signedKeys,
        nonce: nonce,
        expectedServerKey: common.expectedServerKey);

    data.initiator.connected = true;

    logger.d('Switching to responder client handshake');
    return ResponderClientHandshakePhase(
      CommonAfterServerHandshake(common),
      clientHandshakeInput,
      data,
    );
  }
}
