
import 'dart:async';

import 'package:flutter/services.dart';

class FlutterSaltyrtcClient {
  static const MethodChannel _channel = MethodChannel('flutter_saltyrtc_client');

  static Future<String?> get platformVersion async {
    final String? version = await _channel.invokeMethod('getPlatformVersion');
    return version;
  }
}
