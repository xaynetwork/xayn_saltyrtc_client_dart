Implementation of the `SaltyRtc` protocol as specified
here: https://github.com/saltyrtc/saltyrtc-meta/blob/master/Protocol.md

# Usage

The usage is split in two categories:

1. implementing a task
2. using a SaltyRTC with a task

## Using the client

In the second case you need to import `InitiatorClient`/`ResponderClient` from
`flutter_saltyrtc_client/flutter_saltyrtc_client.dart` and set it up with your
task implementation. The setup differs depending on weather it's the initial
peering (no trusted responder, auth token needed) or a later re-peering (public
key of peer is already known).

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

- `ResponderAuthenticated` is emitted once the client to client handshake succeeded,
  it matters during the initial peering as once it's emitted the auth token should
  no longer be used. It's emitted by both kinds of clients and always contains the
  public key of the `Responder` independent of which client emitted it.
- Events specific to the `Task` implementation, like a e.g. `DataReceived`
  event containing some data or a  `DataChannelOpened` event which provides
  a instance allowing sending/receiving data over the data channel.

## Implementing a task.

All relevant types for implementing a task are in
`package:flutter_saltyrtc_client/task.dart`.

Mainly you have to implement two think:

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
but the task still continues, this is useful if the signaling
channel is no longer needed as e.g. a peer-to-peer signaling
channel was opened as part of the task.

# SaltyRtc

SlatyRtc is a signalling protocol using end-to-end encryption.

The idea of this protocol is to allow *two* clients to establish a signaling channel
based on a common server and knowing the per-peering identity (public key) of the
other client. The initial peering relies on transmitting the identity (public key) of the
initiating client as well as a one-time-use token to the other peer using some side-channel,
e.g. by scanning a QR code.

This allows establishing and reestablishing a signaling channel independent of changes
in networking (e.g. changes of IP address), complicated networking topologies or firewalls
(assuming neither WebSockets in general nor the SaltyRTC server are blocked).

This signalling channel then can be used to establish a peer-to-peer connection to the
other client by e.g. using WebRTC or ORTC.

The protocol works by first establishing a secure connection to a server under a specific
path defined through the per-peering identity (public key) of the initiating peer and then
using that to create a end-to-end encrypted tunnel through the server to the given peer.

The *protocol* does *not* rely on the integrity of the server (or any 3rd party) for the security
of the end-to-end encrypted connection. This means it also doesn't rely on the transport layer
security of the used WebSockets (it's still should be used for layering additional security).
It also does *not* rely on the path (i.e. public key) to be a secret. But leaking it to a
malicious 3rd party can make DOS attacks against specific clients easier. Furthermore for
each peering a different identity is (should) be used.

The protocol contains a mechanism to determine a shared *task* (roughly a sub-protocol or extension)
which then gains control over the end-to-end encrypted channel. This implementation does
encapsulate the client to server handshake, client to client handshake and following task phase.
Users of this implementation can (are meant to) implement custom task to use the protocol for
whatever they need.

## Security

The protocol is based on the Networking and Cryptography library (NaCl), through for practical
reasons this implementation uses the `libsodium` fork. It uses the cryptographic
primitives and algorithms provided and endorsed by it as well as following general best practices
around it. For more details are available [in the specification](https://github.com/saltyrtc/saltyrtc-meta/blob/master/Protocol.md#security-mechanisms).

Some outlines:

- Both for client-to-server and client-to-client connections session keys are created and used instead of
  the permanent keys (identity), this provides a reasonable degree of forward security.
- The protocol uses symmetric keys derived from the session key(s) for encrypting packages, with a nonce which
  is a combination of a (crypto-)random cookie, a incremental sequence number with overflow protection as well
  as two bytes used to determine (expected) sender and receiver on given path (that bytes are temporary and
  reused ids which are decoupled from the permanent keys(per-peering identity) of the clients).
- It uses following primitives provided by libsodium
    - mainly: `crypto_box_keypair`, `crypto_box_beforenm`, `crypto_box_open_easy_afternm`, `crypto_box_easy_afternm`
    - for initial one-time-use auth token: `crypto_secretbox_easy`, `crypto_secretbox_open_easy`
    - this means it uses `curve25519` for key exchange `xsalsa20` for encryption and `poly1305` MACs.


Through user of this library should consider following:

- Each client should create a new identity/permanent key pair **for each peering**. The only reason why we allow
  passing in a identity instead of creating a new one every time is because for various use-cases it can be
  necessary that a client needs to be *recreated* (e.g. reestablishing the signalling channel after the app was
  closed and reopened).
- Technically it's possible to transmit not just signaling information but also data over the signalling channel,
  it's not designed to be used to transmit large amounts of data.
- While SaltyRTC can be setup without using TLS for WebSockets it's not recommended.
- While SaltyRTC can be setup without pre-sharing the servers permanent public key
  (!= TLS cert key) it's neither recommended nor supported.
- While we currently export the shared session key of the signaling channel to the task, it's generally not a good
  idea to use it for anything and this will likely be removed in the future.


## SaltyRtc spec compliance/completion

This currently only implements the base protocol and no extensions
on top of it.

This implementation is currently focused on our use-case and
does not implement certain parts of the spec.

### Known missing parts

- The `application` message is currently not supported.
- Using a server without knowing it's public key is
  currently not supported (and generally not a good idea).
- There are some limitation in what you can do with the
  `Task` interface exposed by this library.

Please open a PR if you are interested in implementing this.


# Supported Platforms

Currently following platforms are supported:

- flutter web
- flutter android
- flutter ios

## dart_saltyrtc_client

Most code is unspecific to the actual platform, because of this all
platform independent code is placed in the `dart_saltyrtc_client`
package. All needed parts are re-exported by this package and some of
the usage specific documentation is also placed in this package.