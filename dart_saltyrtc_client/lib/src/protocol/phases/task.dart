import 'dart:typed_data' show Uint8List;

import 'package:dart_saltyrtc_client/src/crypto/crypto.dart'
    show SharedKeyStore;
import 'package:dart_saltyrtc_client/src/messages/id.dart' show Id;
import 'package:dart_saltyrtc_client/src/messages/message.dart' show Message;
import 'package:dart_saltyrtc_client/src/messages/nonce/nonce.dart' show Nonce;
import 'package:dart_saltyrtc_client/src/messages/reader.dart' show readMessage;
import 'package:dart_saltyrtc_client/src/messages/validation.dart'
    show ValidationError;
import 'package:dart_saltyrtc_client/src/protocol/error.dart';
import 'package:dart_saltyrtc_client/src/protocol/peer.dart'
    show Initiator, Peer, Responder;
import 'package:dart_saltyrtc_client/src/protocol/phases/phase.dart'
    show Phase, Common;
import 'package:dart_saltyrtc_client/src/protocol/task.dart';

/// The task phase represents the state of the protocol after the client handshake.
///
/// Besides handling control messages it mostly forward messages to the task
/// specific code.
abstract class TaskPhase extends Phase {
  Peer get pairedPeer;

  //TODO: Can be in TaskPhase, assuming we keep the interface like in java and
  //      don't split it into "ResponderTask" and "InitiatorTask", but I don't
  //      see why we should do so, so this should be fine.
  final Task task;

  TaskPhase(Common common, this.task) : super(common);

  @override
  Phase run(Uint8List msgBytes, Nonce nonce) {
    final sessionKey = getPeerWithId(nonce.source)!.sessionSharedKey!;
    final Uint8List decryptedBytes;
    try {
      decryptedBytes =
          sessionKey.decrypt(ciphertext: msgBytes, nonce: nonce.toBytes());
    } on Exception {
      throw ProtocolError('Could not decrypt task message');
    }

    final msg = readMessage(decryptedBytes);
    if (nonce.source.isServer()) {
      return handleServerMessage(msg);
    } else {
      return handleSignalingMessage(msg);
    }
  }

  //TODO keep naming more in sync with the java code
  Phase handleServerMessage(Message msg);

  Phase handleSignalingMessage(Message msg);

  @override
  Peer? getPeerWithId(Id id) {
    if (id.isServer()) {
      return common.server;
    } else if (id == pairedPeer.id) {
      return pairedPeer;
    } else {
      //FIXME other get peer impl. don't return null??
      // Or change this to return Peer?
      return null;
    }
  }
}

class InitiatorTaskPhase extends TaskPhase {
  @override
  final Responder pairedPeer;

  InitiatorTaskPhase(Common common, this.pairedPeer, Task task)
      : super(common, task);

  @override
  Phase handleServerMessage(Message msg) {
    // TODO: implement handleServerMessage
    throw UnimplementedError();
  }

  @override
  Phase handleSignalingMessage(Message msg) {
    // TODO: implement handleSignalingMessage
    throw UnimplementedError();
  }
}

class ResponderTaskPhase extends TaskPhase {
  @override
  final Initiator pairedPeer;

  ResponderTaskPhase(Common common, this.pairedPeer, Task task)
      : super(common, task);

  @override
  Phase handleServerMessage(Message msg) {
    // TODO: implement handleServerMessage
    throw UnimplementedError();
  }

  @override
  Phase handleSignalingMessage(Message msg) {
    // TODO: implement handleSignalingMessage
    throw UnimplementedError();
  }
}
