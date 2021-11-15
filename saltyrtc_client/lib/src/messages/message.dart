import 'dart:typed_data' show BytesBuilder, Uint8List;

import 'package:equatable/equatable.dart' show EquatableMixin;
import 'package:messagepack/messagepack.dart' show Packer;
import 'package:meta/meta.dart' show protected;
import 'package:xayn_saltyrtc_client/src/crypto/crypto.dart'
    show Crypto, CryptoBox;
import 'package:xayn_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;

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
abstract class Message with EquatableMixin {
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

  /// Builds a SaltyRtc package from this message, nonce and crypto box.
  ///
  /// The caller has to make sure the right crypto box and nonce for the
  /// current current connection state and receiver are used.
  ///
  /// Using `encryptWith=null` means no encryption is done.
  Uint8List buildPackage(Nonce nonce, {required CryptoBox? encryptWith}) {
    final messageBytes = toBytes();
    final nonceBytes = nonce.toBytes();
    final Uint8List payload;
    if (encryptWith == null) {
      payload = messageBytes;
    } else {
      payload = encryptWith.encrypt(message: messageBytes, nonce: nonceBytes);
    }

    final builder = BytesBuilder(copy: false)
      ..add(nonceBytes)
      ..add(payload);
    return builder.takeBytes();
  }
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

/// Data which can be transmitted as part of the task negation.
typedef TaskData = Map<String, Object?>;
typedef TasksData = Map<String, TaskData?>;

const signedKeysLength = Crypto.publicKeyBytes * 2 + Crypto.boxOverhead;
