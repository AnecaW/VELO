import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:bike_computer/main.dart' as app;
import 'package:bike_computer/core/runtime.dart';
import 'package:bike_computer/app/router.dart';
import 'package:bike_computer/services/navigation/gpx_route.dart';
import 'package:bike_computer/features/more/android_apps_screen.dart';
import 'package:bike_computer/features/settings/settings_screen.dart';
import 'package:bike_computer/services/ride/session_codec.dart';
import 'package:bike_computer/features/settings/sensors_screen.dart';
import 'package:bike_computer/features/integrations/connected_apps_screen.dart';
import 'package:bike_computer/features/integrations/gpx_exchange_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android ride lifecycle, actual location availability, maps, training and internal apps',
    (tester) async {
      Future<void> until(Finder finder) async {
        final deadline = DateTime.now().add(const Duration(seconds: 40));
        while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 250));
        }
        expect(finder, findsWidgets);
      }

      await app.main();
      await tester.pump(const Duration(seconds: 3));
      final startupDeadline = DateTime.now().add(const Duration(seconds: 40));
      while (!Runtime.accounts.initialized &&
          DateTime.now().isBefore(startupDeadline)) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      await tester.pump(const Duration(milliseconds: 500));
      if (find.text('Verder zonder account').evaluate().isNotEmpty) {
        await tester.ensureVisible(find.text('Verder zonder account'));
        await tester.tap(find.text('Verder zonder account'));
        await tester.pump(const Duration(milliseconds: 500));
      }
      await until(find.text('Fiets'));
      await tester.pump(const Duration(seconds: 1));
      if (find.text('Herstellen').evaluate().isNotEmpty) {
        await tester.tap(find.text('Herstellen'));
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(find.byTooltip('Gegevensvelden'), findsOneWidget);
      debugPrint('UI ready');
      await tester.tap(find.byTooltip('Gegevensvelden'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.text('Gegevensvelden · versleep om te ordenen'),
        findsOneWidget,
      );
      await tester.tap(find.text('Opslaan'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const ValueKey('ride-start-pause')));
      await tester.pump(const Duration(milliseconds: 500));
      if (find.text('Doorgaan').evaluate().isNotEmpty) {
        await tester.tap(find.text('Doorgaan'));
      }
      await until(find.text('Rit bezig'));
      debugPrint('UI recording');
      final recording = Runtime.ride.service;
      await tester.tap(find.byKey(const ValueKey('tab-1')));
      await tester.pump(const Duration(seconds: 2));
      expect(identical(Runtime.ride.service, recording), isTrue);
      expect(Runtime.ride.session.isRecording, isTrue);
      await tester.tap(find.byKey(const ValueKey('tab-3')));
      await tester.pump(const Duration(seconds: 2));
      expect(Runtime.ride.session.isRecording, isTrue);
      await tester.tap(find.byKey(const ValueKey('tab-0')));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 4));
      await tester.tap(find.byKey(const ValueKey('ride-start-pause')));
      await tester.pump(const Duration(milliseconds: 500));
      await until(find.text('Gepauzeerd'));
      debugPrint('UI paused');
      await tester.tap(find.byKey(const ValueKey('ride-start-pause')));
      await tester.pump(const Duration(milliseconds: 500));
      if (find.text('Doorgaan').evaluate().isNotEmpty) {
        await tester.tap(find.text('Doorgaan'));
      }
      await until(find.text('Rit bezig'));
      debugPrint('UI recording');
      await tester.tap(find.byKey(const ValueKey('ride-stop')));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Opslaan'));
      await tester.pump(const Duration(milliseconds: 500));
      await until(find.text('RIDE SAVED'));
      expect(find.text('RIDE SAVED'), findsOneWidget);
      debugPrint('UI saved');
      final rides = await Runtime.database.getAllRides();
      expect(rides, isNotEmpty);
      final payload = await Runtime.database.getDocument(
        'ride',
        rides.last.rideId,
      );
      final saved = SessionCodec.decode(payload!);
      expect(saved.elapsedTime.inSeconds, greaterThanOrEqualTo(4));
      if (saved.trackPoints.isEmpty) expect(saved.totalDistance, 0);
      router.go('/history');
      debugPrint('Route requested: /history');
      await tester.pump(const Duration(milliseconds: 500));
      await until(find.text('Activiteiten'));
      await tester.tap(find.text('Ride #1'));
      await tester.pump(const Duration(milliseconds: 500));
      await until(find.text('RIDE SAVED'));
      expect(find.text('RIDE SAVED'), findsOneWidget);
      debugPrint('UI saved');
      router.go('/navigation');
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Kaart'), findsWidgets);
      const route = NavRoute('Android offline route', [
        NavPoint(51, 4, 10),
        NavPoint(51.01, 4, 25),
      ]);
      await Runtime.database.putDocument(
        'navigation',
        'selected',
        route.encode(),
      );
      await Runtime.settings.set('keepOn', false);
      router.go('/settings');
      await tester.pump(const Duration(milliseconds: 500));
      await until(find.text('Instellingen'));
      await tester.ensureVisible(find.text('Sensoren'));
      await tester.tap(find.text('Sensoren'));
      await tester.pump(const Duration(milliseconds: 500));
      await until(find.byType(SensorsScreen));
      Navigator.of(tester.element(find.byType(SensorsScreen))).pop();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.scrollUntilVisible(
        find.text('Android-apps'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(SettingsScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('Android-apps'));
      await tester.pump(const Duration(milliseconds: 500));
      await until(find.byType(AndroidAppsScreen));
      expect(find.text('Standaardlauncher instellen'), findsNothing);
      Navigator.of(tester.element(find.byType(AndroidAppsScreen))).pop();
      await tester.pump(const Duration(milliseconds: 500));
      router.go('/more');
      await tester.pump(const Duration(milliseconds: 500));
      await until(find.byKey(const ValueKey('more-list')));
      await tester.scrollUntilVisible(
        find.text('Verbonden apps'),
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('more-list')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('Verbonden apps'));
      await tester.pump(const Duration(milliseconds: 500));
      await until(find.byType(ConnectedAppsScreen));
      await tester.tap(find.text('GPX-bestanden'));
      await tester.pump(const Duration(milliseconds: 500));
      await until(find.byType(GpxExchangeScreen));
      expect(find.text('GPX-route importeren'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
