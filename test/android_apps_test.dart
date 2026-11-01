import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bike_computer/core/platform_bridge.dart';
import 'package:bike_computer/services/android_apps.dart';
import 'package:bike_computer/features/more/android_apps_screen.dart';

class AppsFixture extends AndroidApps {
  bool fail = false, launchFail = false;
  List<AndroidApp> rows = [];
  String? opened;
  @override
  Future<List<AndroidApp>> load({bool refresh = false}) async {
    if (fail) throw PlatformException(code: 'unavailable');
    return rows;
  }

  @override
  Future<void> launch(AndroidApp app) async {
    if (launchFail) throw PlatformException(code: 'missing');
    opened = app.package;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'native app bytes, alphabetical sorting, cache and launch package',
    () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(PlatformBridge.channel, (call) async {
            calls.add(call);
            if (call.method == 'apps') {
              return [
                {
                  'package': 'z',
                  'name': 'Zulu',
                  'icon': Uint8List.fromList([1, 2]),
                },
                {'package': 'a', 'name': 'alpha', 'icon': null},
              ];
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(PlatformBridge.channel, null),
      );
      final service = AndroidApps();
      final apps = await service.load(refresh: true);
      expect(apps.map((a) => a.name), ['alpha', 'Zulu']);
      expect(apps.last.icon, [1, 2]);
      await service.load();
      expect(calls.where((c) => c.method == 'apps').length, 1);
      await service.launch(apps.first);
      expect(calls.last.arguments, 'a');
    },
  );
  testWidgets(
    'app grid opens actual returned package and handles missing app',
    (tester) async {
      final service = AppsFixture()
        ..rows = [const AndroidApp('clock.package', 'Klok', null)];
      await tester.pumpWidget(
        MaterialApp(home: AndroidAppsScreen(service: service)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Klok'));
      expect(service.opened, 'clock.package');
      service.launchFail = true;
      await tester.tap(find.text('Klok'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Mogelijk is ze verwijderd'), findsOneWidget);
    },
  );
  testWidgets('empty app list and retry after platform error', (tester) async {
    final service = AppsFixture()..fail = true;
    await tester.pumpWidget(
      MaterialApp(home: AndroidAppsScreen(service: service)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Opnieuw proberen'), findsOneWidget);
    service.fail = false;
    await tester.tap(find.text('Opnieuw proberen'));
    await tester.pumpAndSettle();
    expect(find.text('Geen te openen Android-apps gevonden.'), findsOneWidget);
  });
  testWidgets('small app grid tolerates long names and enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = AppsFixture()
      ..rows = [
        const AndroidApp('long', 'Een zeer lange Android applicatienaam', null),
      ];
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(1.5),
          ),
          child: child!,
        ),
        home: AndroidAppsScreen(service: service),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
