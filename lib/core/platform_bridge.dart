import 'package:flutter/services.dart';

class PlatformBridge {
  static const channel = MethodChannel('bike_computer/device');
  static Future<T?> call<T>(String method, [dynamic args]) =>
      channel.invokeMethod<T>(method, args);
}
