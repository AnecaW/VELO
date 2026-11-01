import 'dart:typed_data';

import '../core/platform_bridge.dart';

class AndroidApp {
  final String package, name;
  final Uint8List? icon;
  const AndroidApp(this.package, this.name, this.icon);
}

class AndroidApps {
  static List<AndroidApp>? _cache;
  static DateTime? _loaded;
  Future<List<AndroidApp>> load({bool refresh = false}) async {
    if (!refresh &&
        _cache != null &&
        DateTime.now().difference(_loaded!) < const Duration(minutes: 5)) {
      return _cache!;
    }
    final raw = await PlatformBridge.call<List<dynamic>>('apps') ?? [];
    final apps =
        raw.map((row) {
          final map = Map<String, dynamic>.from(row as Map);
          return AndroidApp(
            map['package'] as String,
            map['name'] as String,
            map['icon'] as Uint8List?,
          );
        }).toList()..sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
    _cache = List.unmodifiable(apps);
    _loaded = DateTime.now();
    return _cache!;
  }

  Future<void> launch(AndroidApp app) async {
    await PlatformBridge.call('launch', app.package);
  }
}
