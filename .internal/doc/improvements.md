
# Ideas about Improvements


## Stateful TaskBuilder

```
TaskBuilderFactory
    .name
    .buildInitiator()
        .build()
    .buildResponder()
        .initialData()
        .build()
```

Point is: Do not make it stateless as the
initial handshake isn't necessary stateless,
e.g. you might exchange some session keys for
a new channel.

Alternative: `TaskBuilder.reset()`

## Split out libsodium

`crypto` module => `package:xayn_partial_sodium`


## For Responder Uri API

URI: `<protocol>://<server-domain>[:<port>][/<pathPrefix>]/<hex(publicKey)>?token=<token>[&serverKey=<key>]`

`serverKey` is probably not the best idea

API adds a method to initiator client to build the uri and
a method to create a responder based on it.


## More opinionated API

Provide a more opinionated API which makes a wrong usage
harder and a appropriate usage easier.

- No access to `Identity` and similar.
- Instead have a `Initiator` and `Responder` type which has a
  serialize/deserialize (and update server data) type.
- Then you can create/run the client from the `Initiator`/`Responder`.
- Initiator responder automatically updates once auth token was used
  and triggers a future (to store a updated serialized version).
    - (there is the out of sync gap)
- `Initiator` as `.uri` method (see above)
- `Responder` is build from the uri (only!)
    - (whitelist server keys, and domains etc.)

## `link.taskDone(event)`

Have `SaltyRtcTaskLink.taskDone(event, closeCode)`.

To avoid non-success non-error situations.

## Avoid peering succeeded out-of-sync

Can't be fixed!

- Currently on the initiator side, we can delay
  the "acceptance" until we know the responder
  knowns it's authenticated.
- BUT then the responder has the out-of-sync
  problem as now doesn't know if the initiator
  knowns that it known.
- and so one.
- only way to fix that is to use a timeout
- BUT network delays and it sucks

Similar situation exists for "knowing that it failed".

So what can we do?

- allow users to restart peering from scratch
- Maybe: If the initiator failed before receiving
  a task message and before "x time passed since
  c2c peering succeeded" allow both the responder
  key and auth token for connecting (trial and
  error). Probably not worth it? and might reduce
  security, how likely are network errors exactly
  on the last message send by the initiator in the
  c2c handshake? Also not a perfect solution so
  user restarts from scratch is still needed. So
  really it's not worth it at all!!


## Internal

- encryption method bound to message
- task has a way to "get the right key" for given
  encryption method
