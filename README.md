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

