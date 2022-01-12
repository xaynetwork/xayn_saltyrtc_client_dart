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

@JS()
library sodium_loader;

import 'dart:async' show Completer, Future;
import 'dart:html' show ScriptElement, document, window;
import 'dart:js_util' show getProperty, setProperty;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:js/js.dart' show JS, allowInterop, anonymous;
import 'package:xayn_flutter_saltyrtc_client/src/crypto/sodium.js.dart'
    show LibSodiumJS;

@JS()
@anonymous
class SodiumBrowserInit {
  external void Function(Object sodium) get onload;

  external factory SodiumBrowserInit({void Function(Object sodium) onload});
}

Future<LibSodiumJS> _load() async {
  final completer = Completer<dynamic>();

  setProperty(
    window,
    'sodium',
    SodiumBrowserInit(
      onload: allowInterop(completer.complete),
    ),
  );

  // Load the sodium.js into the page by appending a `<script>` element
  final script = ScriptElement();
  script
    ..type = 'text/javascript'
    ..async = true
    // ignore: unsafe_html
    ..src = 'js/sodium.js';
  document.body!.append(script);

  // await the completer
  final _sodium = await completer.future as LibSodiumJS;
  return _sodium;
}

Future<LibSodiumJS> loadSodiumInBrowser() async {
  // Right now we have an issue to load sodium in the debug version thus we need to do that via the header in the index.html
  // FIXME remove the index.html / load sodium call.
  if (kDebugMode) {
    return getProperty(window, 'sodiumJS') as LibSodiumJS;
  } else {
    return _load();
  }
}
