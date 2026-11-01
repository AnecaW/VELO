import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bike_computer/features/settings/sensors_screen.dart';
import 'package:bike_computer/services/bluetooth/ble_sensor_manager.dart';

void main() {
  testWidgets(
    'sensor page starts empty and explicitly scans injected test hardware',
    (tester) async {
      final manager = BleSensorManager(simulate: true);
      await tester.pumpWidget(
        MaterialApp(home: SensorsScreen(manager: manager)),
      );
      expect(find.text('Polar H10'), findsNothing);
      await tester.tap(find.text('Scan sensoren'));
      await tester.pumpAndSettle();
      expect(find.text('Polar H10'), findsOneWidget);
      expect(find.text('Connect'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
      manager.dispose();
    },
  );
}
