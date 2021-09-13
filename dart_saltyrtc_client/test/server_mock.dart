import 'dart:typed_data' show Uint8List, BytesBuilder;

import 'package:dart_saltyrtc_client/src/crypto/crypto.dart'
    show Crypto, KeyStore, CryptoBox;
import 'package:dart_saltyrtc_client/src/messages/id.dart' show Id, IdResponder;
import 'package:dart_saltyrtc_client/src/messages/message.dart' show Message;
import 'package:dart_saltyrtc_client/src/messages/nonce/cookie.dart'
    show Cookie;
import 'package:dart_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;
import 'package:dart_saltyrtc_client/src/messages/reader.dart' show readMessage;
import 'package:dart_saltyrtc_client/src/messages/s2c/server_auth_initiator.dart'
    show ServerAuthInitiator;
import 'package:dart_saltyrtc_client/src/messages/s2c/server_auth_responder.dart'
    show ServerAuthResponder;
import 'package:dart_saltyrtc_client/src/messages/s2c/server_hello.dart'
    show ServerHello;
import 'package:dart_saltyrtc_client/src/protocol/phases/phase.dart' show Phase;

import 'package:test/test.dart';

typedef Decrypt = Uint8List Function(Uint8List);

class NonceAndMessage<M extends Message> {
  final Nonce nonce;
  final M message;

  static final _getMsg =
      (Uint8List bytes) => Uint8List.sublistView(bytes, Nonce.totalLength);

  NonceAndMessage(this.nonce, this.message);

  NonceAndMessage.fromBytes(Uint8List bytes, [Decrypt? decrypt])
      : nonce = Nonce.fromBytes(bytes),
        message = readMessage((decrypt ?? _getMsg)(bytes)) as M;
}

class IntermediateState<M extends Message> {
  final NonceAndMessage<M> msgSentToClient;
  final Phase phase;

  IntermediateState(this.msgSentToClient, this.phase);
}

/// Provide utils to mock the interaction with the server.
class MockServer {
  final Crypto crypto;
  final KeyStore permanentKeys;
  final KeyStore sessionKeys;
  Nonce nonce;
  Uint8List? clientPermanentPublicKey;

  Uint8List get permanentPublicKey => permanentKeys.publicKey;

  MockServer(this.crypto)
      : permanentKeys = crypto.createKeyStore(),
        sessionKeys = crypto.createKeyStore(),
        nonce = Nonce.fromRandom(
          source: Id.serverAddress,
          destination: Id.unknownAddress,
          randomBytes: crypto.randomBytes,
        );

  /// Decrypt a message that was sent to the server
  Uint8List decrypt(Uint8List bytes) {
    final sks = crypto.createSharedKeyStore(
      ownKeyStore: sessionKeys,
      remotePublicKey: clientPermanentPublicKey!,
    );
    final nonce = Uint8List.sublistView(bytes, 0, Nonce.totalLength);
    final ciphertext = Uint8List.sublistView(bytes, Nonce.totalLength);
    return sks.decrypt(ciphertext: ciphertext, nonce: nonce);
  }

  IntermediateState<ServerHello> sendServerHello(Phase phase) {
    return _send(_serverHello(), phase, encrypt: false);
  }

  IntermediateState<ServerAuthInitiator> sendServerAuthInitiator(
    Phase phase,
    Cookie yourCookie,
    List<IdResponder> responders,
  ) {
    return _send(
      _serverAuthInitiator(yourCookie, responders),
      phase,
      expectSame: false,
    );
  }

  IntermediateState<ServerAuthResponder> sendServerAuthResponder(
    Phase phase,
    Cookie yourCookie,
    bool initiatorConnected,
    IdResponder clientAddress,
  ) {
    return _send(
      _serverAuthResponder(yourCookie, initiatorConnected, clientAddress),
      phase,
      expectSame: false,
    );
  }

  IntermediateState<M> _send<M extends Message>(
    NonceAndMessage<M> nam,
    Phase phase, {
    bool encrypt = true,
    bool expectSame = true,
  }) {
    final messageBytes =
        encrypt ? _encryptMessage(nam) : _unencryptedMessage(nam);
    final nextPhase = phase.handleMessage(messageBytes);
    if (expectSame) {
      expect(nextPhase, equals(phase));
    }

    return IntermediateState(nam, nextPhase);
  }

  NonceAndMessage<ServerAuthResponder> _serverAuthResponder(
    Cookie yourCookie,
    bool initiatorConnected,
    IdResponder clientAddress,
  ) {
    nonce.combinedSequence.next();
    // update with the new address of the client
    nonce = Nonce(
        nonce.cookie, nonce.source, clientAddress, nonce.combinedSequence);
    final signedKeys = _genSignedKeys();
    final msg = ServerAuthResponder(yourCookie, signedKeys, initiatorConnected);
    return NonceAndMessage(nonce, msg);
  }

  NonceAndMessage<ServerAuthInitiator> _serverAuthInitiator(
    Cookie yourCookie,
    List<IdResponder> responders,
  ) {
    nonce.combinedSequence.next();
    // update with the new address of the client
    nonce = Nonce(
      nonce.cookie,
      nonce.source,
      Id.initiatorAddress,
      nonce.combinedSequence,
    );
    final signedKeys = _genSignedKeys();
    final msg = ServerAuthInitiator(yourCookie, signedKeys, responders);
    return NonceAndMessage(nonce, msg);
  }

  /// Encode the message to be sent
  Uint8List _unencryptedMessage<M extends Message>(NonceAndMessage<M> nam) {
    return prepareMessage(nam.message, nam.nonce);
  }

  /// Encode the message to be sent and encrypt it with the session key
  Uint8List _encryptMessage<M extends Message>(NonceAndMessage<M> nam) {
    final sks = crypto.createSharedKeyStore(
        ownKeyStore: sessionKeys, remotePublicKey: clientPermanentPublicKey!);
    return prepareMessage(nam.message, nam.nonce, sks);
  }

  /// Concatenate the server's public session key and the client's public permanent key.
  /// The resulting data is encrypted using the permanent key of the server and the client's public permanent key.
  Uint8List _genSignedKeys() {
    final bytes = BytesBuilder(copy: false);
    bytes.add(sessionKeys.publicKey);
    bytes.add(clientPermanentPublicKey!);
    final keys = bytes.takeBytes();
    final sks = crypto.createSharedKeyStore(
        ownKeyStore: permanentKeys, remotePublicKey: clientPermanentPublicKey!);
    final encrypted = sks.encrypt(message: keys, nonce: nonce.toBytes());
    // encrypt add the nonce at the beginning of the data but we don't want it here
    return Uint8List.sublistView(encrypted, Nonce.totalLength);
  }

  NonceAndMessage<ServerHello> _serverHello() {
    final msg = ServerHello(sessionKeys.publicKey);

    return NonceAndMessage(nonce, msg);
  }
}

Uint8List prepareMessage(Message msg, Nonce nonce, [CryptoBox? box]) {
  final msgBytes = msg.toBytes();
  final nonceBytes = nonce.toBytes();
  if (box != null) {
    return box.encrypt(message: msgBytes, nonce: nonceBytes);
  }

  final bytes = BytesBuilder(copy: false);
  bytes.add(nonceBytes);
  bytes.add(msgBytes);
  return bytes.takeBytes();
}
