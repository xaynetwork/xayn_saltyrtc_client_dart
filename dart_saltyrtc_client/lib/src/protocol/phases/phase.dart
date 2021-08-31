import 'dart:typed_data' show Uint8List, BytesBuilder;

import 'package:dart_saltyrtc_client/src/crypto/crypto.dart'
    show Crypto, AuthToken, KeyStore;
import 'package:dart_saltyrtc_client/src/messages/close_code.dart';
import 'package:dart_saltyrtc_client/src/messages/id.dart' show Id, IdResponder;
import 'package:dart_saltyrtc_client/src/messages/message.dart';
import 'package:dart_saltyrtc_client/src/messages/nonce/combined_sequence.dart';
import 'package:dart_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;
import 'package:dart_saltyrtc_client/src/messages/s2c/drop_responder.dart';
import 'package:dart_saltyrtc_client/src/messages/validation.dart'
    show validateIdResponder, ValidationError;
import 'package:dart_saltyrtc_client/src/protocol/error.dart'
    show ProtocolError;
import 'package:dart_saltyrtc_client/src/protocol/peer.dart'
    show Peer, Responder, Server, Initiator;
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
  final Role role;
  final KeyStore ourKeys;
  final Server server;

  /// Optional permanent key of the server. It can be used to verify the server.
  final Uint8List? expectedServerKey;

  /// How often the server will ping the client.
  final int pingInterval;

  /// Tasks that the user support
  final List<Task> tasks;

  /// Every client start with address set to unknown.
  Id address = Id.unknownAddress;

  Common(
    this.crypto,
    this.ourKeys,
    this.expectedServerKey,
    this.role,
    this.tasks,
    this.pingInterval,
  ) : server = Server(crypto) {
    if (expectedServerKey != null) {
      Crypto.checkPublicKey(expectedServerKey!);
    }
  }
}

/// Additional data for an initiator.
class InitiatorData {
  final Map<IdResponder, Responder> responders = {};

  /// Used to track the oldest responder
  int responderCounter = 0;

  /// Responder trusted key
  final Uint8List? responderTrustedKey;

  /// Selected responder
  Responder? responder;

  InitiatorData(this.responderTrustedKey) {
    if (responderTrustedKey != null) {
      Crypto.checkPublicKey(responderTrustedKey!);
    }
  }
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

  /// Handle a message directly from the WebSocket,
  /// bytes will contains <nonce><message>.
  Phase handleMessage(Uint8List bytes) {
    try {
      final nonce = Nonce.fromBytes(bytes);

      _handleNonce(nonce);

      // remove the nonce
      bytes.removeRange(0, Nonce.totalLength);

      return run(bytes, nonce);
    } on ValidationError catch (e) {
      if (e.isProtocolError) {
        throw ProtocolError('Invalid incoming message: $e');
      } else {
        // TODO log that we are dropping a message
        return this;
      }
    }
  }

  @protected
  Phase run(Uint8List msgBytes, Nonce nonce);

  /// Returns a peer with a given id.
  @protected
  Peer? getPeerWithId(Id id);

  @protected
  void validateNonceSource(Nonce nonce) {
    // this is only valid for ClientHandshake and Handover phases
    // messages in these phases can only come from server or peer
    final source = nonce.source;
    if (source != Id.serverAddress) {
      if (common.role == Role.initiator) {
        validateIdResponder(source.value, 'nonce source');
      } else if (source != Id.initiatorAddress) {
        throw ValidationError(
            'Responder peer message does not come from initiator. Found $source',
            false);
      }
    }
  }

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

    // If we don't encrypt is just the concatenation
    if (!encrypt) {
      final builder = BytesBuilder(copy: false);
      builder.add(nonce.toBytes());
      builder.add(msg.toBytes());
      return builder.takeBytes();
    }

    return receiver.encrypt(msg, nonce);
  }

  /// Send bytes as a message on the websocket channel
  void send(Uint8List bytes) {
    throw UnimplementedError();
  }

  /// Validate the nonce and update the values from it in the peer structure.
  void _handleNonce(Nonce nonce) {
    validateNonceSource(nonce);
    validateNonceDestination(nonce);

    // to validate the combined sequence and the cookie we need the associated peer
    final source = nonce.source;
    final peer = getPeerWithId(nonce.source);
    if (peer == null) {
      throw ProtocolError('Could not find peer $source');
    }

    _validateNonceCs(peer, nonce);
    _validateNonceCookie(peer, nonce);

    // the combined sequence will change with at each message, we update it here.
    peer.csPair.setTheirs(nonce.combinedSequence);
  }

  /// It validates the combined sequence value that a peer send in the nonce.
  /// Returns the peer associated to the source field on the nonce.
  void _validateNonceCs(Peer peer, Nonce nonce) {
    final source = nonce.source;
    final peer = getPeerWithId(source);
    if (peer == null) {
      throw ProtocolError('Could not find peer $source');
    }

    final cspTheirs = peer.csPair.theirs;

    // this is the first message from that sender, the overflow number must be zero
    if (cspTheirs == null) {
      // this if must be separated otherwise the type system does not understand
      // that cspTheirs != null in the else
      if (!nonce.combinedSequence.isOverflowZero) {
        throw ValidationError('First message from $source');
      }
    }
    // this is not the first message, the CS must be incremented
    else if (nonce.combinedSequence <= cspTheirs) {
      throw ValidationError('$source CS must be incremented');
    }
  }

  // this is common between al phases.
  void _validateNonceCookie(Peer peer, Nonce nonce) {
    final cpTheirs = peer.cookiePair.theirs;
    if (cpTheirs != null) {
      if (cpTheirs != nonce.cookie) {
        throw ValidationError('${nonce.source} cookie changed');
      }
    }
  }
}

/// Brings in data an common methods for an initiator.
mixin InitiatorPhase implements Phase {
  InitiatorData get data;

  @override
  Peer? getPeerWithId(Id id) {
    if (id.isServer()) return common.server;
    if (id.isResponder()) {
      return data.responders[id];
    }
    throw ValidationError('Invalid peer id: $id');
  }

  void dropResponder(Responder responder, CloseCode closeCode) {
    data.responders.remove(responder.id);
    final msg = DropResponder(responder.id, closeCode);
    final bytes = buildPacket(msg, responder);
    send(bytes);
  }
}

/// Brings in data an common methods for a responder.
mixin ResponderPhase implements Phase {
  ResponderData get data;

  @override
  Peer? getPeerWithId(Id id) {
    if (id.isServer()) return common.server;
    if (id.isInitiator()) {
      return data.initiator;
    }
    throw ValidationError('Invalid peer id: $id');
  }
}
