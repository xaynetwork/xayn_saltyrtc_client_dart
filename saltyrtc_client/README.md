Implementation of the `SaltyRtc` protocol as specified
here: https://github.com/saltyrtc/saltyrtc-meta/blob/master/Protocol.md

This package contains the platform independent code.
For a ready to use library and usage documentation please see [flutter_saltyrtc_client](../flutter_saltyrtc_client/README.md).

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
security of the used WebSockets (though it still should be used for layering additional security).
It also does *not* rely on the path (i.e. public key) to be a secret. But leaking it to a
malicious 3rd party can make DOS attacks against specific clients easier. Furthermore for
each peering a different identity is (should) be used.

The protocol contains a mechanism to determine a shared *task* (roughly a sub-protocol or extension)
which then gains control over the end-to-end encrypted channel. This implementation
encapsulates the client to server handshake, client to client handshake and the task phase that follows.
Users of this implementation must implement a custom task to use the protocol for
whatever they need.

## Security

The protocol is based on the Networking and Cryptography library (NaCl), though for practical
reasons this implementation uses the `libsodium` fork. It uses the cryptographic
primitives and algorithms provided and endorsed by it as well as following general best practices
around it. More details are available [in the specification](https://github.com/saltyrtc/saltyrtc-meta/blob/master/Protocol.md#security-mechanisms).

Some outlines:

- For both for client-to-server and client-to-client connections session keys are created and used instead of
  the permanent keys (identity). This provides a reasonable degree of forward security.
- The protocol uses symmetric keys derived from the session key(s) for encrypting messages, with a nonce which
  is a combination of a random cookie, an incremental sequence number with overflow protection as well
  as two ids used to determine sender and receiver on given path. These ids are temporary, will be reused and are decoupled from the permanent keys (per-peering identity) of the clients.


Though the user of this library should consider the following:

- Each client should create a new identity/permanent key pair **for each peering**. If a connection
  is established with a previously peered device, the same identity as during the peering must be used.
  This means that if a device is peered with multiple other devices it must have a different identity
  for the peering with each device.
- Technically it's possible to transmit not just signaling information but also arbitrary data over the signaling channel. But that should be avoided as it's not designed to be used to transmit large amounts of data.
- While SaltyRTC can be setup without using TLS for WebSockets, it's not recommended.
- While SaltyRTC can be setup without pre-sharing the server's permanent public key,
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

Please open a PR if you are interested in implementing these.

## Documentation

You can build dart doc by running `flutter pub global run dartdoc`.

## License

See the [NOTICE](NOTICE) file.

### Contribution

Unless you explicitly state otherwise, any contribution intentionally submitted
for inclusion in this project by you, shall be licensed as Apache-2.0, without any additional
terms or conditions.
