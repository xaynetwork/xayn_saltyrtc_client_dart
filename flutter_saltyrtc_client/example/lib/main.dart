import 'dart:async' show Future;
import 'dart:convert' show base64Encode;

import 'package:flutter/material.dart'
    show
        AppBar,
        BuildContext,
        Center,
        Key,
        MaterialApp,
        Scaffold,
        State,
        StatefulWidget,
        Text,
        Widget,
        runApp;
import 'package:flutter_saltyrtc_client/flutter_saltyrtc_client.dart'
    show getCrypto;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _sodiumTest = 'Unknown';

  @override
  void initState() {
    super.initState();
    initCryptoState();
  }

  Future<void> initCryptoState() async {
    final crypto = await getCrypto();

    if (!mounted) return;

    setState(() {
      _sodiumTest = 'nonce: ${base64Encode(crypto.randomBytes(8))}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Center(
          child: Text('Sodium: $_sodiumTest\n'),
        ),
      ),
    );
  }
}
