import 'package:dart_saltyrtc_client/src/crypto/crypto.dart'
    show SharedKeyStore, Crypto;
import 'package:dart_saltyrtc_client/src/messages/id.dart' show Id;
import 'package:dart_saltyrtc_client/src/messages/nonce/combined_sequence.dart'
    show CombinedSequence;
import 'package:dart_saltyrtc_client/src/messages/nonce/cookie.dart'
    show Cookie;
import 'package:dart_saltyrtc_client/src/protocol/states.dart'
    show PeerHandshake;

abstract class Peer {
  final Id id;
  SharedKeyStore? _sessionSharedKey;
  SharedKeyStore? _permanentSharedKey;

  final CombinedSequencePair csp;
  final CookiePair cp;

  Peer(this.id, this.csp, this.cp);

  Peer.fromRandom(this.id, Crypto crypto)
      : csp = CombinedSequencePair.fromRandom(crypto),
        cp = CookiePair.fromRandom(crypto);

  SharedKeyStore? get sessionSharedKey => _sessionSharedKey;

  // A normal setter requires that the return type of the getter is a subtype of the
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
  Server(Crypto crypto) : super.fromRandom(Id.serverAddress, crypto);
}

class Responder extends Peer {
  /// Used to identify the oldest responder during the path cleaning procedure.
  final int counter;

  /// an initiator can receive messages from multiple responder during the peer handshake
  /// we save the state of the handshake for each responder
  PeerHandshake state = PeerHandshake.start;

  Responder(Id id, this.counter, Crypto crypto) : super.fromRandom(id, crypto);
}

class Initiator extends Peer {
  static const initiatorAddress = 1;

  bool connected;

  Initiator(Crypto crypto)
      : connected = false,
        super.fromRandom(Id.initiatorAddress, crypto);
}

class CombinedSequencePair {
  final CombinedSequence ours;
  CombinedSequence? _theirs;

  CombinedSequencePair(this.ours, CombinedSequence this._theirs);

  CombinedSequencePair.fromRandom(Crypto crypto)
      : ours = CombinedSequence.fromRandom(crypto.randomBytes);

  CombinedSequence? get theirs => _theirs;

  // a normal setter require that return type of the getter is a subtype of the
  // type of `cs`. We don't want to be able set null here.
  void setTheirs(CombinedSequence cs) => _theirs = cs;
}

class CookiePair {
  final Cookie ours;
  Cookie? _theirs;

  CookiePair(this.ours, Cookie this._theirs);

  CookiePair.fromRandom(Crypto crypto)
      : ours = Cookie.fromRandom(crypto.randomBytes);

  Cookie? get theirs => _theirs;

  // a normal setter require that return type of the getter is a subtype of the
  // type of `cookie`. We don't want to be able set null here.
  void setTheirs(Cookie cookie) => _theirs = cookie;
}
