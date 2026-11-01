import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bike_computer/core/runtime.dart';
import 'package:bike_computer/features/navigation/navigation_screen.dart';

void main() {
  testWidgets(
    'open navigation reacts immediately to imported offline map settings',
    (tester) async {
      await tester.runAsync(
        () => Future.wait([
          Runtime.settings.set('offlineMap', null),
          Runtime.settings.set('mapEngine', 'raster'),
        ]),
      );
      await tester.pumpWidget(const MaterialApp(home: NavigationScreen()));
      await tester.pumpAndSettle();
      expect(
        find.text('Offline routespoor · geen achtergrondkaart'),
        findsOneWidget,
      );
      await tester.runAsync(
        () => Runtime.settings.set(
          'offlineMap',
          File('test/fixtures/EMULATOR_TEST_MAP.mbtiles').absolute.path,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Offline MBTiles · bronlicentie van bestand'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
