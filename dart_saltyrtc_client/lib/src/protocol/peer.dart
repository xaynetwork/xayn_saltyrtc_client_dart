import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/dart_saltyrtc_client.dart';
import 'package:dart_saltyrtc_client/src/crypto/crypto.dart'
    show AuthToken, Crypto, SharedKeyStore, CryptoBox;
import 'package:dart_saltyrtc_client/src/messages/c2c/key.dart' show Key;
import 'package:dart_saltyrtc_client/src/messages/c2c/token.dart' show Token;
import 'package:dart_saltyrtc_client/src/messages/close_code.dart';
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
    show ProtocolError, ensureNotNull, SaltyRtcError;
import 'package:dart_saltyrtc_client/src/protocol/states.dart'
    show ClientHandshake;
import 'package:meta/meta.dart';

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

  // A normal setter requires that the return type of the getter is a subtype of the
  // type of `sks`. We don't want to be able to set null here.
  void setSessionSharedKey(SharedKeyStore sks) {
    // we need to check that permanent and session are different
    if (sks == permanentSharedKey) {
      throw ProtocolError(
          'Server session key is the same as the permanent key');
    }
    _sessionSharedKey = sks;
  }

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

  Server.fromRandom(Crypto crypto) : super.fromRandom(crypto);

  @protected
  Server(CombinedSequencePair csPair, CookiePair cookiePair)
      : super(csPair, cookiePair);

  @override
  Uint8List encrypt(Message msg, Nonce nonce, [AuthToken? _token]) {
    return _encrypt(msg, nonce, sessionSharedKey);
  }

  /// Return an AuthenticatedServer iff hasSessionSharedKey.
  AuthenticatedServer asAuthenticated() {
    if (!hasSessionSharedKey) {
      throw SaltyRtcError(
        CloseCode.internalError,
        'Server is not authenticated',
      );
    }

    return AuthenticatedServer(
        csPair, cookiePair, permanentSharedKey, sessionSharedKey!);
  }
}

class AuthenticatedServer extends Server {
  @override
  final SharedKeyStore _sessionSharedKey;

  AuthenticatedServer(
    CombinedSequencePair csPair,
    CookiePair cookiePair,
    SharedKeyStore? permanentSharedKey,
    this._sessionSharedKey,
  ) : super(csPair, cookiePair) {
    if (permanentSharedKey != null) {
      setPermanentSharedKey(permanentSharedKey);
    }
  }

  @override
  SharedKeyStore get sessionSharedKey => _sessionSharedKey;

  @override
  void setSessionSharedKey(SharedKeyStore sks) {
    throw SaltyRtcError(
      CloseCode.internalError,
      'Cannot set session key on an already authenticated server',
    );
  }
}

class Responder extends Peer {
  @override
  final IdResponder id;

  /// Used to identify the oldest responder during the path cleaning procedure.
  /// The client keeps a counter of how many responder connected.
  /// This is the value of that counter when this responder connected.
  final int counter;

  /// An initiator can receive messages from multiple responder during the peer handshake
  /// we save the state of the handshake for each responder
  ClientHandshake state = ClientHandshake.start;

  Responder(this.id, this.counter, Crypto crypto) : super.fromRandom(crypto);

  @override
  Uint8List encrypt(Message msg, Nonce nonce, [AuthToken? token]) {
    return _encryptMsg(msg, nonce, permanentSharedKey, sessionSharedKey);
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
    // if it's a Token message we need to use authToken
    if (msg is Token) {
      if (authToken == null) {
        throw ProtocolError(
            'Cannot encrypt token message for peer: auth token is null');
      }
      return _encrypt(msg, nonce, authToken);
    }

    return _encryptMsg(msg, nonce, permanentSharedKey, sessionSharedKey);
  }
}

Uint8List _encrypt(Message msg, Nonce nonce, CryptoBox? key) {
  final sks = ensureNotNull(key);
  return sks.encrypt(message: msg.toBytes(), nonce: nonce.toBytes());
}

/// Encrypt a message by selecting which key we need to use depending on the message itself.
/// If the message is a [Key] message we need to use our permanent key
/// otherwise we use the session key.
Uint8List _encryptMsg(
  Message msg,
  Nonce nonce,
  SharedKeyStore? permanentSharedKey,
  SharedKeyStore? sessionSharedKey,
) {
  final sks = msg is Key ? permanentSharedKey : sessionSharedKey;
  return _encrypt(msg, nonce, sks);
}

class CombinedSequencePair {
  final CombinedSequence ours;
  CombinedSequence? _theirs;

  CombinedSequencePair(this.ours, CombinedSequence this._theirs);

  /// Initialize our data with from random.
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

  /// Initialize our data with from random.
  CookiePair.fromRandom(Crypto crypto)
      : ours = Cookie.fromRandom(crypto.randomBytes);

  Cookie? get theirs => _theirs;

  // A normal setter requires that the return type of the getter is a subtype of the
  // type of `cookie`. We don't want to be able to set null here.
  void setTheirs(Cookie cookie) => _theirs = cookie;
}
