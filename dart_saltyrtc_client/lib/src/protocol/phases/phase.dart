import 'dart:typed_data' show Uint8List, BytesBuilder;

import 'package:dart_saltyrtc_client/src/crypto/crypto.dart'
    show InitialClientAuthMethod, Crypto, AuthToken, KeyStore;
import 'package:dart_saltyrtc_client/src/logger.dart' show logger;
import 'package:dart_saltyrtc_client/src/messages/close_code.dart'
    show CloseCode;
import 'package:dart_saltyrtc_client/src/messages/id.dart'
    show Id, IdClient, IdResponder;
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
    show ProtocolError, SaltyRtcError, ValidationError;
import 'package:dart_saltyrtc_client/src/protocol/network.dart'
    show WebSocketSink;
import 'package:dart_saltyrtc_client/src/protocol/peer.dart'
    show AuthenticatedServer, Client, Initiator, Peer, Server;
import 'package:dart_saltyrtc_client/src/protocol/role.dart' show Role;
import 'package:dart_saltyrtc_client/src/protocol/task.dart' show Task;
import 'package:meta/meta.dart' show protected;

/// The protocol goes through 3 different phases
/// 1. Server handshake
/// 2. Client handshake
/// 3. Handover to the selected task

/// Data that is common to all phases and roles.
class Common {
  final Crypto crypto;
  final KeyStore ourKeys;

  /// Server instance.
  Server server;

  /// Optional permanent key of the server. It can be used to verify the server.
  final Uint8List? expectedServerKey;

  /// Every client start with address set to unknown.
  Id address = Id.unknownAddress;

  /// Sink to send messages to the server or close the connection.
  /// This should not be used directly, use `send` instead.
  WebSocketSink sink;

  Common(
    this.crypto,
    this.ourKeys,
    this.expectedServerKey,
    this.sink,
  ) : server = Server.fromRandom(crypto) {
    if (expectedServerKey != null) {
      Crypto.checkPublicKey(expectedServerKey!);
    }
  }
}

/// Data that is needed for the client handshake and is passed by the user.
class ClientHandshakeInput {
  /// Tasks that the user support
  final List<Task> tasks;

  /// Method to initially authenticate the responder
  /// Trusted public key of the responder we expect to peer with.
  final InitialClientAuthMethod authMethod;

  ClientHandshakeInput({required this.tasks, required this.authMethod});
}

/// Additional data for a responder.
class ResponderData {
  final Initiator initiator;
  AuthToken? authToken;

  ResponderData(this.initiator);
}

/// A phase can handle a message and returns the next phase.
/// This also contains common and auxiliary code.
abstract class Phase {
  /// Data common to all phases and role.
  final Common common;

  Phase(this.common);

  Role get role;

  /// Handle a message directly from the WebSocket,
  /// bytes will contains <nonce><message>.
  Phase handleMessage(Uint8List bytes) {
    Nonce? nonce;
    try {
      nonce = Nonce.fromBytes(bytes);

      final peer = getPeerWithId(nonce.source);
      if (peer == null) {
        // We only handle messages from "known" peers
        // this is in line with the specification.
        logger.w('unexpected package from $nonce');
        return this;
      }

      _handleNonce(peer, nonce);

      final msgBytes = Uint8List.sublistView(bytes, Nonce.totalLength);

      return run(peer, msgBytes, nonce);
    } on ProtocolError catch (e) {
      onProtocolError(e, nonce?.source);
      logger.w('Dropping message(protocol error): $e');
      return this;
    } on StateError catch (e) {
      throw SaltyRtcError(CloseCode.internalError, e.message);
    }
    //TODO on later PR close stream on SaltryRetcError (including
    //`internalError` cases and `NoSharedTaskError`).
  }

  @protected
  void onProtocolError(ProtocolError e, Id? source) {
    throw SaltyRtcError(
        CloseCode.protocolError, 'ProtocolError(with $source): $e');
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
      throw ValidationError(
        'Invalid nonce destination.'
        'Expected $address, found $destination',
      );
    }
  }

  /// Short form for `send(buildPacket(msg, to))`
  void sendMessage(Message msg, {required Peer to, bool encrypted = true}) {
    final type = msg.type;
    send(buildPacket(msg, to, encrypted));
    logger.d('Send $type');
  }

  /// Build binary packet to send.
  Uint8List buildPacket(Message msg, Peer receiver, [bool encrypt = true]) {
    final cs = receiver.csPair.ours;
    try {
      cs.next();
    } on OverflowException {
      throw ProtocolError('CSN overflow');
    }

    final nonce =
        Nonce(receiver.cookiePair.ours, common.address, receiver.id, cs);

    final Uint8List payload;
    if (!encrypt) {
      payload = msg.toBytes();
    } else {
      payload = receiver.encrypt(msg, nonce);
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
}

mixin InitiatorIdentity implements Phase {
  @override
  Role get role => Role.initiator;
}

/// A mixin for anything that expects messages from either the server or a known peer.
mixin WithPeer implements Phase {
  Client get pairedClient;

  @override
  Peer? getPeerWithId(Id id) {
    if (id.isServer()) {
      return common.server;
    } else if (id == pairedClient.id) {
      return pairedClient;
    }
    return null;
  }
}

mixin InitiatorSendDropResponder on Phase {
  void sendDropResponder(IdResponder id, CloseCode closeCode) {
    logger.d('Dropping responder $id');
    sendMessage(DropResponder(id, closeCode), to: common.server);
  }
}

/// Brings in data an common methods for a responder.
mixin ResponderPhase implements Phase {
  ResponderData get data;

  @override
  Role get role => Role.responder;

  @override
  Peer? getPeerWithId(Id id) {
    if (id.isServer()) return common.server;
    if (id.isInitiator()) {
      return data.initiator;
    }
    return null;
  }
}

/// Common methods for phases after the server handshake.
/// Mostly control messages from the server.
abstract class AfterServerHandshakePhase extends Phase {
  @override
  final CommonAfterServerHandshake common;

  AfterServerHandshakePhase(this.common) : super(common);

  void handleSendError(SendError msg) {
    throw UnimplementedError();
  }

  void handleDisconnected(Disconnected msg) {
    throw UnimplementedError();
  }
}

/// Data that is common to all phases and roles after the server handshake.
class CommonAfterServerHandshake extends Common {
  /// After the server handshake the address is an IdClient and it cannot be
  /// modified anymore.
  @override
  final IdClient address;

  /// After the server handshake the session key cannot be nullable anymore.
  @override
  final AuthenticatedServer server;

  CommonAfterServerHandshake(
    Common common,
  )   : address = common.address.asClient(),
        server = common.server.asAuthenticated(),
        super(
          common.crypto,
          common.ourKeys,
          common.expectedServerKey,
          common.sink,
        );
}
