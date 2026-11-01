import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:bike_computer/main.dart' as app;
import 'package:bike_computer/core/runtime.dart';
import 'package:bike_computer/app/router.dart';
import 'package:bike_computer/services/navigation/gpx_route.dart';
import 'package:bike_computer/features/settings/system_screens.dart';
import 'package:bike_computer/services/ride/session_codec.dart';
import 'package:bike_computer/features/settings/sensors_screen.dart';
import 'package:bike_computer/features/integrations/connected_apps_screen.dart';
import 'package:bike_computer/features/integrations/gpx_exchange_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android real GPS ride lifecycle, history, map, settings and launcher',
    (tester) async {
      await app.main();
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('profile-chip-gravel_default')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('START RIDE'));
      await tester.tap(find.text('START RIDE'));
      await tester.pumpAndSettle();
      expect(find.text('READY'), findsOneWidget);
      debugPrint('UI ready');
      await tester.tap(find.byTooltip('Gegevensvelden'));
      await tester.pumpAndSettle();
      expect(
        find.text('Gegevensvelden · versleep om te ordenen'),
        findsOneWidget,
      );
      await tester.tap(find.text('Opslaan'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ride-start-pause')));
      await tester.pumpAndSettle();
      expect(find.text('RECORDING'), findsOneWidget);
      debugPrint('UI recording');
      final recording = Runtime.ride.service;
      await tester.tap(find.byKey(const ValueKey('tab-1')));
      await tester.pump(const Duration(seconds: 2));
      expect(identical(Runtime.ride.service, recording), isTrue);
      expect(Runtime.ride.session.isRecording, isTrue);
      await tester.tap(find.byKey(const ValueKey('tab-3')));
      await tester.pump(const Duration(seconds: 2));
      expect(Runtime.ride.session.isRecording, isTrue);
      await tester.tap(find.byKey(const ValueKey('tab-2')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 4));
      await tester.tap(find.byKey(const ValueKey('ride-start-pause')));
      await tester.pumpAndSettle();
      expect(find.text('PAUSED'), findsOneWidget);
      debugPrint('UI paused');
      await tester.tap(find.byKey(const ValueKey('ride-start-pause')));
      await tester.pumpAndSettle();
      expect(find.text('RECORDING'), findsOneWidget);
      debugPrint('UI recording');
      await tester.tap(find.byKey(const ValueKey('ride-stop')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Opslaan'));
      await tester.pumpAndSettle();
      expect(find.text('RIDE SAVED'), findsOneWidget);
      debugPrint('UI saved');
      final rides = await Runtime.database.getAllRides();
      expect(rides, isNotEmpty);
      final payload = await Runtime.database.getDocument(
        'ride',
        rides.last.rideId,
      );
      expect(SessionCodec.decode(payload!).trackPoints, isNotEmpty);
      router.go('/history');
      await tester.pumpAndSettle();
      expect(find.text('RIDE HISTORY'), findsOneWidget);
      await tester.tap(find.text('Ride #1'));
      await tester.pumpAndSettle();
      expect(find.text('RIDE SAVED'), findsOneWidget);
      debugPrint('UI saved');
      router.go('/navigation');
      await tester.pumpAndSettle();
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
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsWidgets);
      await tester.tap(find.text('Sensors'));
      await tester.pumpAndSettle();
      expect(find.byType(SensorsScreen), findsOneWidget);
      Navigator.of(tester.element(find.byType(SensorsScreen))).pop();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Apps & Launcher'), 300);
      await tester.tap(find.text('Apps & Launcher'));
      await tester.pumpAndSettle();
      expect(find.byType(AppsScreen), findsOneWidget);
      expect(find.text('Standaardlauncher instellen'), findsOneWidget);
      router.go('/more');
      await tester.pumpAndSettle();
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
      await tester.pumpAndSettle();
      expect(find.byType(ConnectedAppsScreen), findsOneWidget);
      await tester.tap(find.text('GPX uitwisselen · zonder server'));
      await tester.pumpAndSettle();
      expect(find.byType(GpxExchangeScreen), findsOneWidget);
      expect(find.text('GPX-route importeren'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
