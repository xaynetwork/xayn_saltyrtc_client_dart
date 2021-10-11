import 'dart:async' show EventSink;
import 'dart:typed_data' show Uint8List, BytesBuilder;

import 'package:dart_saltyrtc_client/src/closer.dart' show Closer;
import 'package:dart_saltyrtc_client/src/crypto/crypto.dart'
    show InitialClientAuthMethod, Crypto, AuthToken, KeyStore;
import 'package:dart_saltyrtc_client/src/logger.dart' show logger;
import 'package:dart_saltyrtc_client/src/messages/close_code.dart'
    show CloseCode, CloseCodeToFromInt;
import 'package:dart_saltyrtc_client/src/messages/id.dart'
    show Id, ClientId, ResponderId;
import 'package:dart_saltyrtc_client/src/messages/message.dart' show Message;
import 'package:dart_saltyrtc_client/src/messages/nonce/combined_sequence.dart'
    show OverflowException;
import 'package:dart_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;
import 'package:dart_saltyrtc_client/src/messages/s2c/disconnected.dart'
    show Disconnected;
import 'package:dart_saltyrtc_client/src/messages/s2c/drop_responder.dart'
    show DropResponder;
import 'package:dart_saltyrtc_client/src/messages/s2c/send_error.dart'
    show SendError;
import 'package:dart_saltyrtc_client/src/protocol/error.dart'
    show ProtocolErrorException, ValidationException;
import 'package:dart_saltyrtc_client/src/protocol/events.dart' show Event;
import 'package:dart_saltyrtc_client/src/protocol/network.dart'
    show WebSocketSink;
import 'package:dart_saltyrtc_client/src/protocol/peer.dart'
    show AuthenticatedServer, Client, Peer, Server;
import 'package:dart_saltyrtc_client/src/protocol/role.dart' show Role;
import 'package:dart_saltyrtc_client/src/protocol/task.dart' show TaskBuilder;
import 'package:dart_saltyrtc_client/src/utils.dart' show EmitEventExt;
import 'package:meta/meta.dart' show immutable, protected;

/// The protocol goes through 3 different phases
/// 1. Server handshake
/// 2. Client handshake
/// 3. Handover to the selected task

/// Data that is common to all phases and roles.
abstract class Common {
  final Crypto crypto;

  /// Server instance.
  Server get server;

  /// Address of this client.
  Id get address;

  /// Sink to send messages to the server or close the connection.
  /// This should not be used directly, use `send` instead.
  WebSocketSink sink;

  /// Mechanism to allow handle all the different ways of closing.
  Closer closer;

  /// Event stream to send to the client.
  EventSink<Event> events;

  Common(
    this.crypto,
    this.sink,
    this.events,
    this.closer,
  );
}

/// Data that is common during the initial setup/server handshake.
class InitialCommon extends Common {
  /// Server instance.
  @override
  Server server;

  /// Every client start with address set to unknown.
  @override
  Id address = Id.unknownAddress;

  InitialCommon(
    Crypto crypto,
    WebSocketSink sink,
    EventSink<Event> events,
    Closer closer,
  )   : server = Server.fromRandom(crypto),
        super(crypto, sink, events, closer);
}

/// Data that is common to all phases and roles after the server handshake.
class AfterServerHandshakeCommon extends Common {
  /// After the server handshake the address is an IdClient and it cannot be
  /// modified anymore.
  @override
  final ClientId address;

  /// After the server handshake the session key cannot be nullable anymore.
  @override
  final AuthenticatedServer server;

  AfterServerHandshakeCommon(
    InitialCommon common,
  )   : address = common.address.asClient(),
        server = common.server.asAuthenticated(),
        super(
          common.crypto,
          common.sink,
          common.events,
          common.closer,
        );
}

/// Config values shared by all people.
@immutable
abstract class Config {
  /// The permanent key of this client.
  final KeyStore permanentKey;
  final int pingInterval;

  /// The expected server permanent public key.
  final Uint8List expectedServerPublicKey;
  final List<TaskBuilder> tasks;

  Config({
    required this.permanentKey,
    required this.tasks,
    required this.expectedServerPublicKey,
    required this.pingInterval,
  }) {
    Crypto.checkPublicKey(expectedServerPublicKey);
  }
}

/// The config for the initiator.
@immutable
class InitiatorConfig extends Config {
  /// Method to initially authenticate the responder.
  final InitialClientAuthMethod authMethod;

  InitiatorConfig({
    required this.authMethod,
    required KeyStore permanentKeys,
    required List<TaskBuilder> tasks,
    required Uint8List expectedServerPublicKey,
    int pingInterval = 0,
  }) : super(
          permanentKey: permanentKeys,
          tasks: tasks,
          expectedServerPublicKey: expectedServerPublicKey,
          pingInterval: pingInterval,
        );
}

/// The config for the responder.
@immutable
class ResponderConfig extends Config {
  /// Auth token used to transmit the clients permanent public key.
  ///
  /// If not given it's assumed the initiator knowns about the clients
  /// public key (through trusted responder mechanism).
  final AuthToken? authToken;

  /// The initiators permanent public key.
  ///
  /// It's known as it's part of the "path" we used to connect to the server.
  final Uint8List initiatorPermanentPublicKey;

  ResponderConfig({
    required KeyStore permanentKeys,
    required List<TaskBuilder> tasks,
    required this.initiatorPermanentPublicKey,
    required Uint8List expectedServerPublicKey,
    this.authToken,
    int pingInterval = 0,
  }) : super(
          permanentKey: permanentKeys,
          tasks: tasks,
          expectedServerPublicKey: expectedServerPublicKey,
          pingInterval: pingInterval,
        ) {
    Crypto.checkPublicKey(initiatorPermanentPublicKey);
  }
}

/// A phase can handle a message and returns the next phase.
/// This also contains common and auxiliary code.
abstract class Phase {
  /// Data common to all phases and role.
  Common get common;

  /// Client Config.
  ///
  /// Use `config` provided by `InitiatorIdentity`/`ResponderIdentity` instead.
  Config get config;

  Phase() {
    common.closer.setCurrentPhase(this);
  }

  Role get role;

  /// Handle a message directly from the WebSocket,
  /// bytes will contains <nonce><message>.
  Phase handleMessage(Uint8List bytes) {
    Nonce? nonce;
    try {
      nonce = Nonce.fromBytes(bytes);

      final peer = getPeerWithId(nonce.source);
      if (peer == null) {
        // We only handle message from "known" peers as per specification
        logger.w('unexpected package from $nonce');
        return this;
      }

      _handleNonce(peer, nonce);

      final msgBytes = Uint8List.sublistView(bytes, Nonce.totalLength);

      return run(peer, msgBytes, nonce);
    } on ProtocolErrorException catch (e) {
      return onProtocolError(e, nonce?.source);
    }
  }

  @protected
  Phase onProtocolError(ProtocolErrorException e, Id? source) {
    common.closer
        .close(e.closeCode, 'ProtocolError($source=>${common.address}): $e');
    //TODO emit event
    return this;
  }

  @protected
  Phase run(Peer source, Uint8List msgBytes, Nonce nonce);

  /// Returns a peer with a given id, if it is not possible it throw a ValidationError.
  @protected
  Peer? getPeerWithId(Id id);

  @protected
  void validateNonceDestination(Nonce nonce) {
    // this is only valid for ClientHandshake and Handover states
    final address = common.address;
    final destination = nonce.destination;
    if (destination != address) {
      throw ValidationException(
        'Invalid nonce destination.'
        'Expected $address, found $destination',
      );
    }
  }

  @protected
  void emitEvent(Event event) => common.events.emitEvent(event);

  /// Short form for `send(buildPacket(msg, to))`
  void sendMessage(
    Message msg, {
    required Peer to,
    bool encrypt = true,
    AuthToken? authToken,
  }) {
    send(buildPacket(msg, to, encrypt: encrypt, authToken: authToken));
    logger.d('Send ${msg.type} to ${to.id}');
  }

  /// Build binary packet to send.
  Uint8List buildPacket(Message msg, Peer receiver,
      {bool encrypt = true, AuthToken? authToken}) {
    final cs = receiver.csPair.ours;
    try {
      cs.next();
    } on OverflowException {
      throw ProtocolErrorException('CSN overflow');
    }

    final nonce =
        Nonce(receiver.cookiePair.ours, common.address, receiver.id, cs);

    final Uint8List payload;
    if (!encrypt) {
      payload = msg.toBytes();
    } else {
      payload = receiver.encrypt(msg, nonce, authToken);
    }

    final builder = BytesBuilder(copy: false)
      ..add(nonce.toBytes())
      ..add(payload);
    return builder.takeBytes();
  }

  /// Send bytes as a message on the websocket channel
  void send(Uint8List bytes) {
    // the java implementation takes the bytes and the original message,
    // if we are in the handover state the message  is sent to the task and it
    // have to encrypt it before sending it, otherwise the bytes are sent on the
    // websocket channel. This design allow the task to implement its own chunking
    // and reduce the overhead of a message but it also move some encryption logic
    // to the task it self. At the moment I pref to keep the code simpler.
    common.sink.add(bytes);
  }

  /// Validate the nonce and update the values from it in the peer structure.
  void _handleNonce(Peer peer, Nonce nonce) {
    validateNonceDestination(nonce);
    final source = nonce.source;
    peer.csPair.updateAndCheck(nonce.combinedSequence, source);
    peer.cookiePair.updateAndCheck(nonce.cookie, source);
  }

  /// Called when we are in the process of being closed.
  ///
  /// The returned `int?` is the status code used as close code for
  /// the WebSocket connection.
  int? doClose(CloseCode? closeCode, bool wasCanceled) => closeCode?.toInt();
}

mixin InitiatorIdentity implements Phase {
  @override
  Role get role => Role.initiator;
}

mixin ResponderIdentity implements Phase {
  @override
  Role get role => Role.responder;
}

/// A mixin for anything that expects messages from either the server or a known peer.
mixin WithPeer implements Phase {
  Client? get pairedClient;

  @override
  Peer? getPeerWithId(Id id) {
    if (id.isServer()) {
      return common.server;
    } else if (id == pairedClient?.id) {
      return pairedClient;
    }
    return null;
  }
}

mixin InitiatorSendDropResponder on Phase {
  void sendDropResponder(ResponderId id, CloseCode closeCode) {
    logger.d('Dropping responder $id');
    sendMessage(DropResponder(id, closeCode), to: common.server);
  }
}

/// Common methods for phases after the server handshake.
/// Mostly control messages from the server.
abstract class AfterServerHandshakePhase extends Phase {
  @override
  final AfterServerHandshakeCommon common;

  AfterServerHandshakePhase(this.common) : super();

  Phase handleSendError(SendError msg) {
    if (msg.source != common.address) {
      throw ProtocolErrorException(
          'received send-error for message not send by us');
    }
    final destination = msg.destination;
    final viableDestination = role == Role.initiator
        ? msg.destination.isResponder()
        : msg.destination.isInitiator();
    if (!viableDestination) {
      throw ProtocolErrorException(
          'received send-error for unexpected destination $destination');
    }
    return handleSendErrorByDestination(destination);
  }

  Phase handleSendErrorByDestination(Id destination);

  Phase handleDisconnected(Disconnected msg);
}
