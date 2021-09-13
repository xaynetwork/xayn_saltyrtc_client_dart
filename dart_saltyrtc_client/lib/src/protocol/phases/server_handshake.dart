import 'dart:typed_data' show Uint8List, BytesBuilder;

import 'package:collection/collection.dart' show ListEquality;
import 'package:dart_saltyrtc_client/src/logger.dart' show logger;
import 'package:dart_saltyrtc_client/src/messages/close_code.dart'
    show CloseCode;
import 'package:dart_saltyrtc_client/src/messages/id.dart' show Id, IdResponder;
import 'package:dart_saltyrtc_client/src/messages/message.dart'
    show MessageType, Message, MessageFields;
import 'package:dart_saltyrtc_client/src/messages/nonce/cookie.dart'
    show Cookie;
import 'package:dart_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;
import 'package:dart_saltyrtc_client/src/messages/reader.dart' show readMessage;
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
    show ValidationError, validateIdResponder;
import 'package:dart_saltyrtc_client/src/protocol/error.dart'
    show ProtocolError, ensureNotNull;
import 'package:dart_saltyrtc_client/src/protocol/peer.dart' show Responder;
import 'package:dart_saltyrtc_client/src/protocol/phases/client_handshake.dart'
    show ClientHandshakePhase;
import 'package:dart_saltyrtc_client/src/protocol/phases/client_handshake_initiator.dart'
    show InitiatorClientHandshakePhase;
import 'package:dart_saltyrtc_client/src/protocol/phases/client_handshake_responder.dart'
    show ResponderClientHandshakePhase;
import 'package:dart_saltyrtc_client/src/protocol/phases/phase.dart'
    show
        Common,
        CommonAfterServerHandshake,
        Phase,
        InitiatorData,
        InitiatorPhase,
        ResponderData,
        ResponderPhase,
        ClientHandshakeInput;
import 'package:dart_saltyrtc_client/src/protocol/role.dart' show Role;
import 'package:dart_saltyrtc_client/src/protocol/states.dart'
    show ClientHandshake;
import 'package:meta/meta.dart' show protected;

const saltyrtcSubprotocol = 'v1.saltyrtc.org';

enum ServerHandshakeState { start, helloSent, authSent, done }

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
  void handleServerAuth(Message msg, Nonce nonce);

  @protected
  void sendClientHello();

  @protected
  ClientHandshakePhase goToClientHandshakePhase();

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
      // server handshake is done so we can use the general implementation
      case ServerHandshakeState.done:
        super.validateNonceDestination(nonce);
    }
  }

  @override
  Phase run(Uint8List msgBytes, Nonce nonce) {
    // the first message is not encrypted
    if (handshakeState != ServerHandshakeState.start) {
      final sks = ensureNotNull(common.server.sessionSharedKey);
      msgBytes = sks.decrypt(ciphertext: msgBytes, nonce: nonce.toBytes());
    }

    final msg = readMessage(msgBytes);
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
        }
        break;
      case ServerHandshakeState.helloSent:
        throw ProtocolError(
            'Received ${msg.type} message before sending ${MessageType.clientAuth}');
      case ServerHandshakeState.authSent:
        {
          handleServerAuth(msg, nonce);
        }
        break;
      case ServerHandshakeState.done:
        StateError(
          'Received server handshake message when it is already finished',
        );
    }

    logger.v('Current server handshake status $handshakeState');

    // Check if we're done yet
    if (handshakeState == ServerHandshakeState.done) {
      return goToClientHandshakePhase();
    } else {
      return this;
    }
  }

  void handleServerHello(ServerHello msg, Nonce nonce) {
    final sks = common.crypto.createSharedKeyStore(
        ownKeyStore: common.ourKeys, remotePublicKey: msg.key);
    common.server.setSessionSharedKey(sks);
    common.server.cookiePair.setTheirs(nonce.cookie);
  }

  void sendClientAuth() {
    final serverCookie = ensureNotNull(common.server.cookiePair.theirs);
    final subprotocols = [saltyrtcSubprotocol];
    final msg = ClientAuth(
      serverCookie,
      common.expectedServerKey,
      subprotocols,
      _pingInterval,
    );

    final bytes = buildPacket(msg, common.server);
    send(bytes);
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
    with InitiatorPhase {
  @override
  final InitiatorData data;

  InitiatorServerHandshakePhase(
    Common common,
    ClientHandshakeInput clientHandshakeInput,
    int pingInterval,
    this.data,
  ) : super(common, clientHandshakeInput, pingInterval);

  @override
  ClientHandshakePhase goToClientHandshakePhase() {
    logger.d('Switching to initiator client handshake');

    return InitiatorClientHandshakePhase(
      CommonAfterServerHandshake(common),
      clientHandshakeInput,
      data,
    );
  }

  @override
  void sendClientHello() {
    // noop as an initiator
  }

  @override
  void handleServerAuth(Message msg, Nonce nonce) {
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

    msg.responders.forEach(processNewResponder);

    handshakeState = ServerHandshakeState.done;
  }

  void processNewResponder(IdResponder id) {
    // discard previous responder with same id
    data.responders.remove(id);

    final responder = Responder(id, data.responderCounter++, common.crypto);
    final responderTrustedKey = data.responderTrustedKey;
    // we already have the permanent key of the responder
    if (responderTrustedKey != null) {
      // we have the token
      responder.state = ClientHandshake.token;
      try {
        final sks = common.crypto.createSharedKeyStore(
            ownKeyStore: common.ourKeys, remotePublicKey: responderTrustedKey);
        responder.setPermanentSharedKey(sks);
      } on ValidationError {
        throw StateError('Invalid responder trusted key');
      }
    }

    data.responders[responder.id] = responder;

    // if we have more then this responders we drop the oldest
    const responderSizeThreshold = 252;

    if (data.responders.length > responderSizeThreshold) {
      _dropOldestInactiveResponder();
    }
  }

  void _dropOldestInactiveResponder() {
    final responder = data.responders.entries
        .where((entry) => entry.value.state == ClientHandshake.start)
        .fold<Responder?>(null, (min, entry) {
      final v = entry.value;
      if (min == null) {
        return v;
      }

      return min.counter < v.counter ? min : v;
    });

    if (responder != null) {
      dropResponder(responder, CloseCode.droppedByInitiator);
    }
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
  ClientHandshakePhase goToClientHandshakePhase() {
    logger.d('Switching to responder client handshake');

    return ResponderClientHandshakePhase(
      CommonAfterServerHandshake(common),
      clientHandshakeInput,
      data,
    );
  }

  @override
  void sendClientHello() {
    logger.d('Switching to responder client handshake');

    final msg = ClientHello(common.ourKeys.publicKey);
    final bytes = buildPacket(msg, common.server, false);
    send(bytes);
    handshakeState = ServerHandshakeState.helloSent;
  }

  @override
  void handleServerAuth(Message msg, Nonce nonce) {
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

    handshakeState = ServerHandshakeState.done;
  }
}
