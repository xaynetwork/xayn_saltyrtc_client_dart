
Implementation of the SaltyRtc protocol.

Take a look at the [README in `flutter_saltyrtc_client`](./flutter_saltyrtc_client/README.md)
for more documentation and examples.


# Contributing

TODO license/contribution terms

## Documentation

- You can build dart doc by running `flutter pub global run dartdoc` in
  the `flutter_slatyrtc_client` and `dart_slatyrtc_client` directories.

## Testing

### Run integration tests

To run integration tests we need the server.

Installation:
```bash
python3 -m venv venv
venv/bin/pip install "saltyrtc.server[logging]"
```

The dart library is not able to connect using tls if the server
has self-signed certificate. Because of this we disable tls on
the server side with `SALTY_SAFETY_OFF`.
```bash
export SALTYRTC_SERVER_PERMANENT_KEY="0919b266ce1855419e4066fc076b39855e728768e3afa773105edd2e37037c20"
SALTYRTC_SAFETY_OFF='yes-and-i-know-what-im-doing' ./venv/bin/saltyrtc-server -v 5 serve -p 8765 -k $SALTYRTC_SERVER_PERMANENT_KEY
```


