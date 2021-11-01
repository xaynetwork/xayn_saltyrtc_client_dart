@JS()
library sodium_loader;

import 'dart:async' show Completer, Future;
import 'dart:html' show ScriptElement, document, window;
import 'dart:js_util' show getProperty, setProperty;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_saltyrtc_client/src/crypto/sodium.js.dart'
    show LibSodiumJS;
import 'package:js/js.dart' show JS, allowInterop, anonymous;

@JS()
@anonymous
class SodiumBrowserInit {
  external void Function(dynamic sodium) get onload;

  external factory SodiumBrowserInit({void Function(dynamic sodium) onload});
}

Future<LibSodiumJS> _load() async {
  final completer = Completer<dynamic>();

  setProperty(
      window,
      'sodium',
      SodiumBrowserInit(
        onload: allowInterop(completer.complete),
      ));

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
