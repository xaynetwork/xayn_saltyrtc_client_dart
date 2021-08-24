/// Client handshake intermediate states.
/// Depending on the role the meaning can be different.
///
enum ClientHandshake {
  start,
  token,
  keySent,
  keyReceived,
  authSent,
  authReceived,
}
