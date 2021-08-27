import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/src/crypto/crypto.dart'
    show AuthToken, Crypto, SharedKeyStore;
import 'package:dart_saltyrtc_client/src/messages/c2c/key.dart' show Key;
import 'package:dart_saltyrtc_client/src/messages/c2c/token.dart' show Token;
import 'package:dart_saltyrtc_client/src/messages/id.dart' show Id;
import 'package:dart_saltyrtc_client/src/messages/id.dart'
    show Id, IdResponder, IdServer, IdInitiator;
import 'package:dart_saltyrtc_client/src/messages/message.dart' show Message;
import 'package:dart_saltyrtc_client/src/messages/nonce/combined_sequence.dart'
    show CombinedSequence;
import 'package:dart_saltyrtc_client/src/messages/nonce/cookie.dart'
    show Cookie;
import 'package:dart_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;
import 'package:dart_saltyrtc_client/src/protocol/error.dart'
    show ProtocolError, ensureNotNull;
import 'package:dart_saltyrtc_client/src/protocol/states.dart'
    show ClientHandshake;

/// A peer can be the server, the initiator or a responder
abstract class Peer {
  SharedKeyStore? _sessionSharedKey;
  SharedKeyStore? _permanentSharedKey;

  final CombinedSequencePair csPair;
  final CookiePair cookiePair;

  Id get id;

  Peer(this.csPair, this.cookiePair);

  Peer.fromRandom(Crypto crypto)
      : csPair = CombinedSequencePair.fromRandom(crypto),
        cookiePair = CookiePair.fromRandom(crypto);

  Uint8List encrypt(Message msg, Nonce nonce, [AuthToken? token]);

  SharedKeyStore? get sessionSharedKey => _sessionSharedKey;

  // A normal setter requires that return type of the getter is a subtype of the
  // type of `sks`. We don't want to be able to set null here.
  void setSessionSharedKey(SharedKeyStore sks) => _sessionSharedKey = sks;

  bool get hasSessionSharedKey => _sessionSharedKey != null;

  SharedKeyStore? get permanentSharedKey => _permanentSharedKey;

  // A normal setter requires that the return type of the getter is a subtype of the
  // type of `sks`. We don't want to be able to set null here.
  void setPermanentSharedKey(SharedKeyStore sks) => _permanentSharedKey = sks;

  bool get hasPermanentSharedKey => _permanentSharedKey != null;
}

class Server extends Peer {
  @override
  final IdServer id = Id.serverAddress;

  Server(Crypto crypto) : super.fromRandom(crypto);

  @override
  Uint8List encrypt(Message msg, Nonce nonce, [AuthToken? token]) {
    final sks = ensureNotNull(sessionSharedKey);
    return sks.encrypt(message: msg.toBytes(), nonce: nonce.toBytes());
  }
}

class Responder extends Peer {
  @override
  final IdResponder id;

  /// Used to identify the oldest responder during the path cleaning procedure.
  final int counter;

  /// An initiator can receive messages from multiple responder during the peer handshake
  /// we save the state of the handshake for each responder
  ClientHandshake state = ClientHandshake.start;

  Responder(this.id, this.counter, Crypto crypto) : super.fromRandom(crypto);

  @override
  Uint8List encrypt(Message msg, Nonce nonce, [AuthToken? token]) {
    final SharedKeyStore sks;
    // if it's a Key message we need to use our permanent key
    if (msg is Key) {
      sks = ensureNotNull(permanentSharedKey);
    } else {
      // other messages will be encrypted with the session key
      sks = ensureNotNull(sessionSharedKey);
    }
    return sks.encrypt(message: msg.toBytes(), nonce: nonce.toBytes());
  }
}

class Initiator extends Peer {
  @override
  final IdInitiator id = Id.initiatorAddress;

  bool connected;

  Initiator(Crypto crypto)
      : connected = false,
        super.fromRandom(crypto);

  @override
  Uint8List encrypt(Message msg, Nonce nonce, [AuthToken? authToken]) {
    final msgBytes = msg.toBytes();
    final nonceBytes = msg.toBytes();
    // if it's a Token message we need to use authToken
    if (msg is Token) {
      if (authToken == null) {
        throw ProtocolError(
            'Cannot encrypt token message for peer: auth token is null');
      }
      return authToken.encrypt(message: msgBytes, nonce: nonceBytes);
    }

    final SharedKeyStore sks;
    if (msg is Key) {
      sks = ensureNotNull(permanentSharedKey);
    } else {
      // other messages will be encrypted with the session key
      sks = ensureNotNull(sessionSharedKey);
    }
    return sks.encrypt(message: msgBytes, nonce: nonceBytes);
  }
}

class CombinedSequencePair {
  final CombinedSequence ours;
  CombinedSequence? _theirs;

  CombinedSequencePair(this.ours, CombinedSequence this._theirs);

  CombinedSequencePair.fromRandom(Crypto crypto)
      : ours = CombinedSequence.fromRandom(crypto.randomBytes);

  CombinedSequence? get theirs => _theirs;

  // A normal setter require that the return type of the getter is a subtype of the
  // type of `cs`. We don't want to be able to set null here.
  void setTheirs(CombinedSequence cs) => _theirs = cs;
}

class CookiePair {
  final Cookie ours;
  Cookie? _theirs;

  CookiePair(this.ours, Cookie this._theirs);

  CookiePair.fromRandom(Crypto crypto)
      : ours = Cookie.fromRandom(crypto.randomBytes);

  Cookie? get theirs => _theirs;

  // A normal setter requires that the return type of the getter is a subtype of the
  // type of `cookie`. We don't want to be able to set null here.
  void setTheirs(Cookie cookie) => _theirs = cookie;
}
