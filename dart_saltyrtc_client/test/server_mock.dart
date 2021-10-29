import 'dart:typed_data' show Uint8List, BytesBuilder;

import 'package:dart_saltyrtc_client/src/crypto/crypto.dart'
    show KeyStore, CryptoBox;
import 'package:dart_saltyrtc_client/src/messages/id.dart' show Id, ResponderId;
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

import 'crypto_mock.dart' show crypto;

typedef Decrypt = Uint8List Function(Uint8List);

class NonceAndMessage<M extends Message> {
  final Nonce nonce;
  final M message;

  static Uint8List _getMsg(Uint8List bytes) =>
      Uint8List.sublistView(bytes, Nonce.totalLength);

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
  final KeyStore permanentKeys;
  final KeyStore sessionKeys;
  Nonce nonce;
  Uint8List? clientPermanentPublicKey;

  Uint8List get permanentPublicKey => permanentKeys.publicKey;

  MockServer()
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

  IntermediateState<ServerHello> sendServerHelloToPhase(Phase phase) {
    return _sendToPhase(serverHello(), phase, encrypt: false);
  }

  IntermediateState<ServerAuthInitiator> sendServerAuthInitiatorToPhase(
    Phase phase,
    Cookie yourCookie,
    List<ResponderId> responders,
  ) {
    return _sendToPhase(
      serverAuthInitiator(yourCookie, responders),
      phase,
      expectSame: false,
    );
  }

  IntermediateState<ServerAuthResponder> sendServerAuthResponderToPhase(
    Phase phase,
    Cookie yourCookie,
    bool initiatorConnected,
    ResponderId clientAddress,
  ) {
    return _sendToPhase(
      serverAuthResponder(yourCookie, initiatorConnected, clientAddress),
      phase,
      expectSame: false,
    );
  }

  Uint8List buildMessage<M extends Message>(
    NonceAndMessage<M> nam, {
    bool encrypt = true,
  }) {
    CryptoBox? encryptWith;
    if (encrypt) {
      encryptWith = crypto.createSharedKeyStore(
          ownKeyStore: sessionKeys, remotePublicKey: clientPermanentPublicKey!);
    }
    return nam.message.buildPackage(nam.nonce, encryptWith: encryptWith);
  }

  IntermediateState<M> _sendToPhase<M extends Message>(
    NonceAndMessage<M> nam,
    Phase phase, {
    bool encrypt = true,
    bool expectSame = true,
  }) {
    final messageBytes = buildMessage(nam, encrypt: encrypt);

    final nextPhase = phase.handleMessage(messageBytes);
    expect(nextPhase.isClosingWsStream, isFalse);
    if (expectSame) {
      expect(nextPhase, equals(phase));
    }
    return IntermediateState(nam, nextPhase);
  }

  NonceAndMessage<ServerAuthResponder> serverAuthResponder(
    Cookie yourCookie,
    bool initiatorConnected,
    ResponderId clientAddress,
  ) {
    nonce.combinedSequence.next();
    // update with the new address of the client
    nonce = Nonce(
        nonce.cookie, nonce.source, clientAddress, nonce.combinedSequence);
    final signedKeys = _genSignedKeys();
    final msg = ServerAuthResponder(yourCookie, signedKeys, initiatorConnected);
    return NonceAndMessage(nonce, msg);
  }

  NonceAndMessage<ServerAuthInitiator> serverAuthInitiator(
    Cookie yourCookie,
    List<ResponderId> responders,
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

  /// Concatenate the server's public session key and the client's public permanent key.
  /// The resulting data is encrypted using the permanent key of the server and the client's public permanent key.
  Uint8List _genSignedKeys() {
    final bytes = BytesBuilder(copy: false);
    bytes.add(sessionKeys.publicKey);
    bytes.add(clientPermanentPublicKey!);
    final keys = bytes.takeBytes();
    final sks = crypto.createSharedKeyStore(
        ownKeyStore: permanentKeys, remotePublicKey: clientPermanentPublicKey!);
    return sks.encrypt(message: keys, nonce: nonce.toBytes());
  }

  NonceAndMessage<ServerHello> serverHello() {
    final msg = ServerHello(sessionKeys.publicKey);

    return NonceAndMessage(nonce, msg);
  }
}
