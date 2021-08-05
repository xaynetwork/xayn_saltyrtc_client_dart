import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/src/crypto/crypto.dart' show Crypto;
import 'package:messagepack/messagepack.dart' show Packer;
import 'package:meta/meta.dart' show protected;

/// Different types of messages in the SaltyRTC Singnal protocol.
/// This is not exhaustive since a task can define its own types.
class MessageType {
  MessageType._();

  static const clientHello = 'client-hello';
  static const clientAuth = 'client-auth';
  static const disconnected = 'disconnected';
  static const dropResponder = 'drop-responder';
  static const serverAuth = 'server-auth';
  static const newInitiator = 'new-initiator';
  static const newResponder = 'new-responder';
  static const sendError = 'send-error';
  static const serverHello = 'server-hello';
  static const close = 'close';
  static const key = 'key';
  static const application = 'application';
  static const auth = 'auth';
  static const token = 'token';
}

/// All messages in the protocol extend this.
abstract class Message {
  /// Type of the message
  String get type;

  /// Encode the message using MessagePack.
  Uint8List toBytes() {
    // TODO set bufSize to a suitable value
    final msgPacker = Packer();

    write(msgPacker);

    return msgPacker.takeBytes();
  }

  /// Each message encode itself using MessagePack.
  @protected
  void write(Packer msgPacker);
}

/// Fields of the MessagePack encoded data.
class MessageFields {
  MessageFields._();

  static const type = 'type';
  static const key = 'key';
  static const yourCookie = 'your_cookie';
  static const subprotocols = 'subprotocols';
  static const pingInterval = 'ping_interval';
  static const yourKey = 'your_key';
  static const id = 'id';
  static const reason = 'reason';
  static const responders = 'responders';
  static const signedKeys = 'signed_keys';
  static const initiatorConnected = 'initiator_connected';
  static const data = 'data';
  static const task = 'task';
  static const tasks = 'tasks';
}

const signedKeysLength = Crypto.publicKeyBytes * 2 + Crypto.boxOverhead;
