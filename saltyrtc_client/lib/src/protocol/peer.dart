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
import 'package:xayn_saltyrtc_client/src/crypto/crypto.dart'
    show AuthToken, Crypto, SharedKeyStore, CryptoBox;
import 'package:xayn_saltyrtc_client/src/messages/c2c/key.dart' show Key;
import 'package:xayn_saltyrtc_client/src/messages/c2c/token.dart' show Token;
import 'package:xayn_saltyrtc_client/src/messages/id.dart' show Id;
import 'package:xayn_saltyrtc_client/src/messages/id.dart'
    show Id, ResponderId, ServerId, InitiatorId;
import 'package:xayn_saltyrtc_client/src/messages/message.dart' show Message;
import 'package:xayn_saltyrtc_client/src/messages/nonce/combined_sequence.dart'
    show CombinedSequence;
import 'package:xayn_saltyrtc_client/src/messages/nonce/cookie.dart'
    show Cookie;
import 'package:xayn_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;
import 'package:xayn_saltyrtc_client/src/protocol/error.dart'
    show ProtocolErrorException, ValidationException;

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

  Peer._fromParts({
    required SharedKeyStore? sessionSharedKey,
    required SharedKeyStore? permanentSharedKey,
    required this.cookiePair,
    required this.csPair,
  })  : _sessionSharedKey = sessionSharedKey,
        _permanentSharedKey = permanentSharedKey;

  Uint8List encrypt(Message msg, Nonce nonce, [AuthToken? token]);

  SharedKeyStore? get sessionSharedKey => _sessionSharedKey;

  // A normal setter requires that the return type of the getter is a subtype of the
  // type of `sks`. We don't want to be able to set null here.
  void setSessionSharedKey(SharedKeyStore sks) {
    // we need to check that permanent and session are different
    if (sks.remotePublicKey == permanentSharedKey?.remotePublicKey) {
      throw const ProtocolErrorException(
        'Server session key is the same as the permanent key',
      );
    }
    _sessionSharedKey = sks;
  }

  bool get hasSessionSharedKey => _sessionSharedKey != null;

  SharedKeyStore? get permanentSharedKey => _permanentSharedKey;

  // A normal setter requires that the return type of the getter is a subtype of the
  // type of `sks`. We don't want to be able to set null here.
  void setPermanentSharedKey(SharedKeyStore sks) => _permanentSharedKey = sks;

  bool get hasPermanentSharedKey => _permanentSharedKey != null;

  bool get isAuthenticated =>
      hasSessionSharedKey &&
      hasPermanentSharedKey &&
      cookiePair.theirs != null &&
      csPair.theirs != null;
}

class Server extends Peer {
  @override
  final ServerId id = Id.serverAddress;

  Server.fromRandom(Crypto crypto) : super.fromRandom(crypto);

  @protected
  Server(CombinedSequencePair csPair, CookiePair cookiePair)
      : super(csPair, cookiePair);

  Server._fromParts({
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

  @override
  Uint8List encrypt(Message msg, Nonce nonce, [AuthToken? token]) {
    return _encrypt(msg, nonce, sessionSharedKey!);
  }

  /// Return an AuthenticatedServer iff hasSessionSharedKey.
  AuthenticatedServer asAuthenticated() =>
      AuthenticatedServer._fromUnauthenticated(this);
}

mixin AuthenticatedPeer implements Peer {
  @override
  SharedKeyStore get sessionSharedKey => _sessionSharedKey!;
  @override
  SharedKeyStore get permanentSharedKey => _permanentSharedKey!;

  @override
  void setSessionSharedKey(SharedKeyStore sks) {
    throw StateError(
      'Cannot set session key on an already authenticated server',
    );
  }

  @override
  void setPermanentSharedKey(SharedKeyStore sks) {
    throw StateError(
      'Cannot set permanent key on an already authenticated server',
    );
  }
}

class AuthenticatedServer extends Server with AuthenticatedPeer {
  /// Creates an AuthenticatedServer (throw an exception if it's not possible).
  ///
  /// To create an `AuthenticatedServer` a *shallow* copy of the passed in
  /// `Server` is made.
  AuthenticatedServer._fromUnauthenticated(Server unauthenticated)
      : super._fromParts(
          sessionSharedKey: unauthenticated.sessionSharedKey,
          permanentSharedKey: unauthenticated.permanentSharedKey,
          cookiePair: unauthenticated.cookiePair,
          csPair: unauthenticated.csPair,
        ) {
    if (!unauthenticated.isAuthenticated) {
      throw StateError('Server is not authenticated');
    }
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
  final ResponderId id;

  Responder(this.id, Crypto crypto) : super.fromRandom(crypto);

  Responder._fromParts({
    required this.id,
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

  @override
  Uint8List encrypt(Message msg, Nonce nonce, [AuthToken? token]) {
    return _encryptMsg(msg, nonce, permanentSharedKey, sessionSharedKey);
  }

  AuthenticatedResponder assertAuthenticated() =>
      AuthenticatedResponder._fromUnauthenticated(this);
}

class Initiator extends Client {
  @override
  final InitiatorId id = Id.initiatorAddress;

  Initiator(Crypto crypto) : super.fromRandom(crypto);

  Initiator._fromParts({
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

  @override
  Uint8List encrypt(Message msg, Nonce nonce, [AuthToken? token]) {
    // if it's a Token message we need to use authToken
    if (msg is Token) {
      if (token == null) {
        throw const ProtocolErrorException(
          'Cannot encrypt token message for peer: auth token is null',
        );
      }
      return _encrypt(msg, nonce, token);
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
    if (!unauthenticated.isAuthenticated) {
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
        ) {
    if (!unauthenticated.isAuthenticated) {
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
        throw ValidationException('First message from $source with overflow');
      }
      _theirs = csnFromMessage.copy();
    } else {
      theirs!.next();
      if (theirs != csnFromMessage) {
        throw ValidationException('$source CS must be incremented by 1');
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
        throw ValidationException('$source reused our cookie');
      } else {
        _theirs = cookieFromMessage;
      }
    } else if (theirs != cookieFromMessage) {
      throw ValidationException('Cookie of $source changed');
    }
  }
}
