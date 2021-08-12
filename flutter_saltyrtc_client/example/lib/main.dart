import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_saltyrtc_client/crypto/crypto_provider.dart';

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
    await CryptoProvider.init();

    if (!mounted) return;

    setState(() {
      _sodiumTest =
          'nonce: ${base64Encode(CryptoProvider.instance.randomBytes(8))}';
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
