This package provide a ready to use client for the SaltyRTC protocol.
For more details about the actual implementation of the protocol and
some limitation of this library please see [xayn_saltyrtc_client](../saltyrtc_client/README.md).

# Usage

The usage is split in two categories:

1. implementing a task
2. using a SaltyRTC with a task

## Using the client

In the second case you need to import `InitiatorClient`/`ResponderClient` from
`xayn_flutter_saltyrtc_client/flutter_saltyrtc_client.dart` and set it up with your
task implementation. The setup differs depending on whether it's the peering, i.e.
the initial connection to the peer (no trusted responder, auth token needed),
or a later connection with an already peered client (public key of the responder
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
`package:xayn_flutter_saltyrtc_client/task.dart`.

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
done. Besides asynchronously running arbitrary code it can emit
events (and receive events emitted by the client), close the
client and send task messages. It also can trigger a handover
in which case the signaling channel gets closed by the task
but the task still continues. This is useful if the signaling
channel is no longer needed e.g. a peer-to-peer signaling
channel was opened as part of the task.

# Supported Platforms

Currently the following platforms are supported:

- flutter android
- flutter ios
- flutter web

## License

xayn_flutter_saltyrtc_client and its components, unless otherwise stated, are licensed under
 * APACHE-2.0 ([LICENSE](LICENSE)).

## Contribution

Unless you explicitly state otherwise, any contribution intentionally submitted for inclusion in the work by you,
as defined in the Apache-2.0 license, shall be licensed as above, without any additional terms or conditions.
