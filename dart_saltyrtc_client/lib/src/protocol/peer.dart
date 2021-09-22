import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/src/crypto/crypto.dart'
    show AuthToken, Crypto, SharedKeyStore, CryptoBox;
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
    show ProtocolError, ValidationError;
import 'package:meta/meta.dart' show protected;

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

  Peer._fromParts(
      {required SharedKeyStore? sessionSharedKey,
      required SharedKeyStore? permanentSharedKey,
      required this.cookiePair,
      required this.csPair})
      : _sessionSharedKey = sessionSharedKey,
        _permanentSharedKey = permanentSharedKey;

  Uint8List encrypt(Message msg, Nonce nonce, [AuthToken? token]);

  SharedKeyStore? get sessionSharedKey => _sessionSharedKey;

  // A normal setter requires that the return type of the getter is a subtype of the
  // type of `sks`. We don't want to be able to set null here.
  void setSessionSharedKey(SharedKeyStore sks) {
    // we need to check that permanent and session are different
    if (sks.remotePublicKey == permanentSharedKey?.remotePublicKey) {
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
    return _encrypt(msg, nonce, sessionSharedKey!);
  }

  /// Return an AuthenticatedServer iff hasSessionSharedKey.
  AuthenticatedServer asAuthenticated() {
    if (!hasSessionSharedKey) {
      throw StateError('Server is not authenticated');
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
    throw StateError(
      'Cannot set session key on an already authenticated server',
    );
  }
}

/// Only needed to avoid to get a Server when we only want a Responder or an Initiator.
abstract class Client extends Peer {
  Client(CombinedSequencePair csPair, CookiePair cookiePair)
      : super(csPair, cookiePair);

  Client.fromRandom(Crypto crypto) : super.fromRandom(crypto);

  Client._fromParts({
    required SharedKeyStore? sessionSharedKey,
    required SharedKeyStore? permanentSharedKey,
    required CookiePair cookiePair,
    required CombinedSequencePair csPair,
  }) : super._fromParts(
          sessionSharedKey: sessionSharedKey,
          permanentSharedKey: permanentSharedKey,
          cookiePair: cookiePair,
          csPair: csPair,
        );
}

class Responder extends Client {
  @override
  final IdResponder id;

  Responder(this.id, Crypto crypto) : super.fromRandom(crypto);

  Responder._fromParts(
      {required this.id,
      required SharedKeyStore? sessionSharedKey,
      required SharedKeyStore? permanentSharedKey,
      required CookiePair cookiePair,
      required CombinedSequencePair csPair})
      : super._fromParts(
          sessionSharedKey: sessionSharedKey,
          permanentSharedKey: permanentSharedKey,
          cookiePair: cookiePair,
          csPair: csPair,
        );

  @override
  Uint8List encrypt(Message msg, Nonce nonce, [AuthToken? token]) {
    return _encryptMsg(msg, nonce, permanentSharedKey, sessionSharedKey);
  }

  AuthenticatedResponder assertAuthenticated() =>
      AuthenticatedResponder._fromUnauthenticated(this);
}

class Initiator extends Client {
  @override
  final IdInitiator id = Id.initiatorAddress;

  bool connected;

  Initiator(Crypto crypto)
      : connected = false,
        super.fromRandom(crypto);

  Initiator._fromParts(
      {required SharedKeyStore? sessionSharedKey,
      required SharedKeyStore? permanentSharedKey,
      required CookiePair cookiePair,
      required CombinedSequencePair csPair,
      required this.connected})
      : super._fromParts(
          sessionSharedKey: sessionSharedKey,
          permanentSharedKey: permanentSharedKey,
          cookiePair: cookiePair,
          csPair: csPair,
        );

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

  AuthenticatedInitiator assertAuthenticated() =>
      AuthenticatedInitiator._fromUnauthenticated(this);
}

Uint8List _encrypt(Message msg, Nonce nonce, CryptoBox key) {
  return key.encrypt(message: msg.toBytes(), nonce: nonce.toBytes());
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
  return _encrypt(msg, nonce, sks!);
}

mixin AuthenticatedPeer implements Peer {
  @override
  SharedKeyStore get sessionSharedKey => _sessionSharedKey!;
  @override
  SharedKeyStore get permanentSharedKey => _permanentSharedKey!;
}

class AuthenticatedResponder extends Responder with AuthenticatedPeer {
  /// Creates an AuthenticatedResponder (throw an exception if it's not possible).
  ///
  /// To create an `AuthenticatedResponder` a *shallow* copy of the passed in
  /// `Responder` is made.
  AuthenticatedResponder._fromUnauthenticated(Responder unauthenticated)
      : super._fromParts(
          sessionSharedKey: unauthenticated.sessionSharedKey,
          permanentSharedKey: unauthenticated.permanentSharedKey,
          cookiePair: unauthenticated.cookiePair,
          csPair: unauthenticated.csPair,
          id: unauthenticated.id,
        ) {
    if (unauthenticated.sessionSharedKey == null ||
        unauthenticated.permanentSharedKey == null ||
        unauthenticated.cookiePair.theirs == null ||
        unauthenticated.csPair.theirs == null) {
      throw StateError('Responder is not authenticated');
    }
  }
}

class AuthenticatedInitiator extends Initiator with AuthenticatedPeer {
  /// Creates an AuthenticatedInitiator (throw an exception if it's not possible).
  ///
  /// To create an `AuthenticatedInitiator` a *shallow* copy of the passed in
  /// `Initiator` is made.
  AuthenticatedInitiator._fromUnauthenticated(Initiator unauthenticated)
      : super._fromParts(
          sessionSharedKey: unauthenticated.sessionSharedKey,
          permanentSharedKey: unauthenticated.permanentSharedKey,
          cookiePair: unauthenticated.cookiePair,
          csPair: unauthenticated.csPair,
          connected: unauthenticated.connected,
        ) {
    if (unauthenticated.sessionSharedKey == null ||
        unauthenticated.permanentSharedKey == null ||
        unauthenticated.cookiePair.theirs == null ||
        unauthenticated.csPair.theirs == null ||
        !unauthenticated.connected) {
      throw StateError('Initiator is not authenticated');
    }
  }
}

class CombinedSequencePair {
  final CombinedSequence ours;
  CombinedSequence? _theirs;

  CombinedSequencePair(this.ours, CombinedSequence this._theirs);

  /// Initialize our data with from random.
  CombinedSequencePair.fromRandom(Crypto crypto)
      : ours = CombinedSequence.fromRandom(crypto.randomBytes);

  CombinedSequence? get theirs => _theirs;

  /// Check and update the peers combined sequence number (CSN) pair based
  /// on the CSN from the received message.
  void updateAndCheck(CombinedSequence csnFromMessage, Id source) {
    // this is the first message from that sender, the overflow number must be zero
    if (theirs == null) {
      if (!csnFromMessage.isOverflowZero) {
        throw ValidationError('First message from $source with overflow');
      }
      _theirs = csnFromMessage.copy();
    } else {
      theirs!.next();
      if (theirs != csnFromMessage) {
        throw ValidationError('$source CS must be incremented by 1');
      }
    }
  }
}

class CookiePair {
  final Cookie ours;
  Cookie? _theirs;

  CookiePair(this.ours, Cookie this._theirs);

  /// Initialize our data with from random.
  CookiePair.fromRandom(Crypto crypto)
      : ours = Cookie.fromRandom(crypto.randomBytes);

  Cookie? get theirs => _theirs;

  /// Check and update the peers cookie pair based on the
  /// cookie from the received message.
  void updateAndCheck(Cookie cookieFromMessage, Id source) {
    if (theirs == null) {
      if (ours == cookieFromMessage) {
        throw ValidationError('$source reused our cookie');
      } else {
        _theirs = cookieFromMessage;
      }
    } else if (theirs != cookieFromMessage) {
      throw ValidationError('Cookie of $source changed');
    }
  }
}
