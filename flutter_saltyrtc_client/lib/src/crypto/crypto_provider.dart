// Copyright 2021 Xayn AG
//
// Licensed under the Apache License, Version 2.0 (the License);
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'package:xayn_flutter_saltyrtc_client/src/crypto/crypto_provider_stub.dart'
    if (dart.library.io) 'crypto_provider_dart.dart'
    if (dart.library.js) 'crypto_provider_web.dart';
import 'package:xayn_saltyrtc_client/crypto.dart' show Crypto;

Future<Crypto>? _instance;
Future<Crypto> getCrypto() {
  _instance ??= loadCrypto();
  return _instance!;
}
