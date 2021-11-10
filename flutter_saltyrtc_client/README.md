Implementation of the `SaltyRtc` protocol as specified
here: https://github.com/saltyrtc/saltyrtc-meta/blob/master/Protocol.md

# Usage

The usage is split in two categories:

1. implementing a task
2. using a SaltyRTC with a task

## Using the client

In the second case you need to import `InitiatorClient`/`ResponderClient` from
`flutter_saltyrtc_client/flutter_saltyrtc_client.dart` and set it up with your
task implementation. The setup differs depending on whether it's the peering, i.e.
the initial connection to the peer (no trusted responder, auth token needed).
Or a later connection with a already peered client (public key of the responder
is already known to the initiator).

Then you would use it like a loop similar too:

```dart
try {
    await for(final event in client.run()) {
        // handle events
    }
    // handle non error closed
} on ClosingErrorEvent catch (e, st) {
    // handle error
}
```

Most emitted events are various sub-types of `ClosingErrorEvent` (which are
pushed to the stream using `addError` and as such thrown when received), or
events mostly relevant for analytics or fine-tuning retry/back-of logic.

There are a few other relevant events:

- `ResponderAuthenticated` is emitted once the client to client handshake succeeded.
  It matters during the initial peering as once it's emitted the auth token must
  no longer be used. It's emitted by both kinds of clients and always contains the
  public key of the `Responder` independent of which client emitted it.
- Events specific to the `Task` implementation, like a `DataReceived`
  event containing some data or a  `DataChannelOpened` event which provides
  an instance allowing sending/receiving data over the data channel.

## Implementing a task.

All relevant types for implementing a task are in
`package:flutter_saltyrtc_client/task.dart`.

Mainly you have to implement two interfaces:

- `TaskBuilder` which is used to build the task during the
  client to client handshake
- `Task` which is created by the `TaskBuilder`

The `TaskBuilder` can be used to exchange some initial
information (e.g. settings) during the client to client
handshake (but be aware that the task selection doesn't
consider this information). This can be helpful to speed
things up by reducing the number of task messages which
need to be exchanged.

The `Task` takes over when the client to client handshake is
done, besides asynchronous running arbitrary code it can emit
events (and receive events emitted by the client), close the
client and send task messages. It also can trigger a handover
in which case the signaling channel gets closed by the task
but the task still continues. This is useful if the signaling
channel is no longer needed as e.g. a peer-to-peer signaling
channel was opened as part of the task.

# SaltyRtc

SaltyRtc is a signaling protocol using end-to-end encryption.

The idea of this protocol is to allow *two* clients to establish a signaling channel
based on a common server and knowing the per-peering identity (public key) of the
other client. The initial peering relies on transmitting the identity (public key) of the
initiating client as well as a one-time-use token to the other peer using some side-channel,
e.g. by scanning a QR code.

This allows establishing and reestablishing a signaling channel independent of changes
in networking (e.g. changes of IP address), complicated networking topologies or firewalls
(assuming neither WebSockets in general nor the SaltyRTC server are blocked).

This signaling channel then can be used to establish a peer-to-peer connection to the
other client by e.g. using WebRTC or ORTC.

The protocol works by first establishing a secure connection to a server under a specific
path defined through the per-peering identity (public key) of the initiating peer and then
using that to create an end-to-end encrypted tunnel through the server to the given peer.

The protocol does *not* rely on the integrity of the server (or any 3rd party) for the security
of the end-to-end encrypted connection. This means it also doesn't rely on the transport layer
security of the used WebSockets (it still should be used for layering additional security).
It also does *not* rely on the path (i.e. public key) to be a secret. But leaking it to a
malicious 3rd party can make DOS attacks against specific clients easier. Furthermore for
each peering a different identity is (should) be used.

The protocol contains a mechanism to determine a shared *task* (roughly a sub-protocol or extension)
which then gains control over the end-to-end encrypted channel. This implementation does
encapsulate the client to server handshake, client to client handshake and following task phase.
Users of this implementation must implement a custom task to use the protocol for
whatever they need.

## Security

The protocol is based on the Networking and Cryptography library (NaCl), though for practical
reasons this implementation uses the `libsodium` fork. It uses the cryptographic
primitives and algorithms provided and endorsed by it as well as following general best practices
around it. More details are available [in the specification](https://github.com/saltyrtc/saltyrtc-meta/blob/master/Protocol.md#security-mechanisms).

Some outlines:

- Both for client-to-server and client-to-client connections session keys are created and used instead of
  the permanent keys (identity), this provides a reasonable degree of forward security.
- The protocol uses symmetric keys derived from the session key(s) for encrypting packages, with a nonce which
  is a combination of a (crypto-)random cookie, an incremental sequence number with overflow protection as well
  as two bytes used to determine (expected) sender and receiver on given path (that bytes are temporary and
  reused ids which are decoupled from the permanent keys (per-peering identity) of the clients).


Though the user of this library should consider the following:

- Each client should create a new identity/permanent key pair **for each peering**. If a connection
  is established with a previous paired device the same identity as during the peering must be used.
  This means that if a device is peered with multiple other devices it must have a different identity
  for the peering with each device.
- Technically it's possible to transmit not just signaling information but also data over the signaling channel,
  it's not designed to be used to transmit large amounts of data.
- While SaltyRTC can be setup without using TLS for WebSockets it's not recommended.
- While SaltyRTC can be setup without pre-sharing the servers permanent public key
  (!= TLS cert key) it's neither recommended nor supported.

## SaltyRtc spec compliance/completion

This currently only implements the base protocol and no extensions
on top of it.

This implementation is currently focused on our use-case and
does not implement certain parts of the spec.

### Known missing parts

- The `application` message is currently not supported.
- Using a server without knowing its public key is
  currently not supported (and generally not a good idea).
- There are some limitations in what you can do with the
  `Task` interface exposed by this library.

Please open a PR if you are interested in implementing this.


# Supported Platforms

Currently the following platforms are supported:

- flutter web
- flutter android
- flutter ios

## dart_saltyrtc_client

Most code is not specific to the actual platform. Because of this all
platform independent code is placed in the `dart_saltyrtc_client`
package. All needed parts are re-exported by this package and some of
the usage specific documentation is also placed in this package.