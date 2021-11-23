/// Exposes the internally used crypto utilities so that tasks can use them.
///
/// This allows us to not import/include libsodium twice,
/// but in the future there should be an independent package.
///
/// If tasks establish peer-to-peer channels they sometimes need to implement
/// encryption for such channels, there are two ways to do so using this
/// library:
///
/// - using [KeyStore], [SharedKeyStore]
/// - using [SecretStream]
///
/// The later one is strongly recommended as it uses libsodiums
/// `crypto_secretstream_*` API under the hood which handles the
/// nonce for us as well as protection against reordering attacks
/// while adding some additional features and a more simple to use API.
///
/// # Example Using [SecretStream]
///
/// ```dart
/// final msg = Uint8List.fromList([33, 44, 55, 12]);
/// final crypto = await getCrypto();
///
/// // in peer A
/// final ssbOfA = crypto.createKXSecretStreamBuilder(onePeerTrueOneFalse: true);
///
/// // in peer B
/// final ssbOfB = crypto.createKXSecretStreamBuilder(onePeerTrueOneFalse: false);
///
/// // we "somehow" send the public keys to the other peer,
/// // e.g. by embedding the public key in the TaskData returned by TaskBuilder
/// final ssOfA = ssbOfA.build(ssbOfB.publicKey);
/// final ssOfB = ssbOfB.build(ssbOfA.publicKey);
///
/// // send msg from A to B
/// final encryptedMsg = ssOfA.encryptPackage(msg);
/// final decryptedMsg = ssOfB.decryptPackage(encryptedMsg);
///
/// // send msg from B to A
/// final encryptedMsg = ssOfB.encryptPackage(msg);
/// final decryptedMsg = ssOfA.decryptPackage(encryptedMsg);
/// ```
library crypto;

export 'package:xayn_flutter_saltyrtc_client/src/crypto/crypto_provider.dart'
    show getCrypto;
export 'package:xayn_saltyrtc_client/crypto.dart';
