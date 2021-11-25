import 'dart:typed_data' show Uint8List, BytesBuilder;

import 'package:collection/collection.dart' show ListEquality;
import 'package:meta/meta.dart' show protected;
import 'package:xayn_saltyrtc_client/events.dart' as events;
import 'package:xayn_saltyrtc_client/src/logger.dart' show logger;
import 'package:xayn_saltyrtc_client/src/messages/id.dart' show Id;
import 'package:xayn_saltyrtc_client/src/messages/message.dart'
    show MessageType, Message, MessageFields;
import 'package:xayn_saltyrtc_client/src/messages/nonce/cookie.dart'
    show Cookie;
import 'package:xayn_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;
import 'package:xayn_saltyrtc_client/src/messages/reader.dart'
    show MessageDecryptionExt, readMessage;
import 'package:xayn_saltyrtc_client/src/messages/s2c/client_auth.dart'
    show ClientAuth;
import 'package:xayn_saltyrtc_client/src/messages/s2c/client_hello.dart'
    show ClientHello;
import 'package:xayn_saltyrtc_client/src/messages/s2c/server_auth_initiator.dart'
    show ServerAuthInitiator;
import 'package:xayn_saltyrtc_client/src/messages/s2c/server_auth_responder.dart'
    show ServerAuthResponder;
import 'package:xayn_saltyrtc_client/src/messages/s2c/server_hello.dart'
    show ServerHello;
import 'package:xayn_saltyrtc_client/src/messages/validation.dart'
    show validateResponderId;
import 'package:xayn_saltyrtc_client/src/protocol/error.dart'
    show ProtocolErrorException, ValidationException;
import 'package:xayn_saltyrtc_client/src/protocol/peer.dart' show Peer;
import 'package:xayn_saltyrtc_client/src/protocol/phases/client_handshake_initiator.dart'
    show InitiatorClientHandshakePhase;
import 'package:xayn_saltyrtc_client/src/protocol/phases/client_handshake_responder.dart'
    show ResponderClientHandshakePhase;
import 'package:xayn_saltyrtc_client/src/protocol/phases/phase.dart'
    show
        AfterServerHandshakeCommon,
        InitialCommon,
        InitiatorConfig,
        InitiatorIdentity,
        Phase,
        ResponderConfig,
        ResponderIdentity;
import 'package:xayn_saltyrtc_client/src/protocol/role.dart' show Role;

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
  @override
  final InitialCommon common;

  ServerHandshakeState handshakeState = ServerHandshakeState.start;

  ServerHandshakePhase(this.common) : super() {
    // We can directly create the shared permanent key
    common.server.setPermanentSharedKey(
      common.crypto.createSharedKeyStore(
        ownKeyStore: config.permanentKey,
        remotePublicKey: config.expectedServerPublicKey,
      ),
    );
  }

  @protected
  Phase handleServerAuth(Message msg, Nonce nonce);

  @protected
  void sendClientHello();

  @override
  void validateNonceDestination(Nonce nonce) {
    final destination = nonce.destination;

    void check(Id expected) {
      if (destination != expected) {
        throw ValidationException(
          'Receive message with invalid nonce destination. '
          'Expected $expected, found $destination',
        );
      }
    }

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
          validateResponderId(destination.value, 'nonce destination');
        }
        return;
    }
  }

  @override
  Peer? getPeerWithId(Id id) {
    if (id.isServer()) return common.server;
    return null;
  }

  @override
  Phase run(Peer source, Uint8List msgBytes, Nonce nonce) {
    // the first message is not encrypted
    final Message msg;
    if (handshakeState == ServerHandshakeState.start) {
      msg = readMessage(msgBytes);
    } else {
      msg = common.server.sessionSharedKey!.readEncryptedMessage(
        msgBytes: msgBytes,
        nonce: nonce,
      );
    }

    switch (handshakeState) {
      case ServerHandshakeState.start:
        if (msg is ServerHello) {
          handleServerHello(msg, nonce);
          sendClientHello();
          sendClientAuth();
        } else {
          throw ProtocolErrorException(
            'Expected ${MessageType.serverHello}, but got ${msg.type}',
          );
        }
        logger.v('Current server handshake status $handshakeState');
        return this;
      case ServerHandshakeState.helloSent:
        throw ProtocolErrorException(
          'Received ${msg.type} message before sending ${MessageType.clientAuth}',
        );
      case ServerHandshakeState.authSent:
        final clientPhase = handleServerAuth(msg, nonce);
        emitEvent(events.ServerHandshakeDone());
        return clientPhase;
    }
  }

  void handleServerHello(ServerHello msg, Nonce nonce) {
    final sks = common.crypto.createSharedKeyStore(
      ownKeyStore: config.permanentKey,
      remotePublicKey: msg.key,
    );
    common.server.setSessionSharedKey(sks);
  }

  void sendClientAuth() {
    final serverCookie = common.server.cookiePair.theirs!;
    final subprotocols = [saltyrtcSubprotocol];
    sendMessage(
      ClientAuth(
        serverCookie,
        config.expectedServerPublicKey,
        subprotocols,
        config.pingInterval,
      ),
      to: common.server,
    );
    handshakeState = ServerHandshakeState.authSent;
  }

  /// Validate the signed keys sent by the server.
  void validateSignedKey({
    required Uint8List? signedKey,
    required Nonce nonce,
  }) {
    if (signedKey == null) {
      throw ValidationException(
        'Server did not send ${MessageFields.signedKeys} in ${MessageType.serverAuth} message',
      );
    }

    final decrypted = common.server.permanentSharedKey!.decrypt(
      ciphertext: signedKey,
      nonce: nonce.toBytes(),
    );
    final sks = common.server.sessionSharedKey!;
    final expected = BytesBuilder(copy: false)
      ..add(sks.remotePublicKey)
      ..add(config.permanentKey.publicKey);
    if (!ListEquality<int>().equals(decrypted, expected.takeBytes())) {
      throw ValidationException(
        'Decrypted ${MessageFields.signedKeys} in ${MessageType.serverAuth} message is invalid',
      );
    }
  }

  void validateRepeatedCookie(Cookie cookie) {
    if (cookie != common.server.cookiePair.ours) {
      throw ProtocolErrorException(
        'Bad repeated cookie in ${MessageType.serverAuth} message',
      );
    }
  }
}

class InitiatorServerHandshakePhase extends ServerHandshakePhase
    with InitiatorIdentity {
  @override
  final InitiatorConfig config;

  InitiatorServerHandshakePhase(
    InitialCommon common,
    this.config,
  ) : super(common);

  @override
  void sendClientHello() {
    // noop as an initiator
  }

  @override
  Phase handleServerAuth(Message msg, Nonce nonce) {
    logger.d('Initiator server handshake handling server-auth');

    if (msg is! ServerAuthInitiator) {
      throw ProtocolErrorException('Message is not ${MessageType.serverAuth}');
    }

    if (!nonce.destination.isInitiator()) {
      throw ValidationException(
        'Invalid none destination ${nonce.destination}',
      );
    }

    common.address = Id.initiatorAddress;

    validateRepeatedCookie(msg.yourCookie);

    validateSignedKey(signedKey: msg.signedKeys, nonce: nonce);

    logger.d('Switching to initiator client handshake');
    final nextPhase = InitiatorClientHandshakePhase(
      AfterServerHandshakeCommon(common),
      config,
    );
    msg.responders.forEach(nextPhase.addNewResponder);
    return nextPhase;
  }
}

class ResponderServerHandshakePhase extends ServerHandshakePhase
    with ResponderIdentity {
  @override
  final ResponderConfig config;

  ResponderServerHandshakePhase(
    InitialCommon common,
    this.config,
  ) : super(common);

  @override
  void sendClientHello() {
    logger.d('Switching to responder client handshake');
    sendMessage(
      ClientHello(config.permanentKey.publicKey),
      to: common.server,
      encrypt: false,
    );
    handshakeState = ServerHandshakeState.helloSent;
  }

  @override
  Phase handleServerAuth(Message msg, Nonce nonce) {
    if (msg is! ServerAuthResponder) {
      throw ProtocolErrorException('Message is not ${MessageType.serverAuth}');
    }

    if (!nonce.destination.isResponder()) {
      throw ValidationException(
        'Invalid none destination ${nonce.destination}',
      );
    }

    // this is our address from the server
    common.address = nonce.destination;

    validateRepeatedCookie(msg.yourCookie);

    validateSignedKey(signedKey: msg.signedKeys, nonce: nonce);

    logger.d('Switching to responder client handshake');
    return ResponderClientHandshakePhase(
      AfterServerHandshakeCommon(common),
      config,
      initiatorConnected: msg.initiatorConnected,
    );
  }
}
