import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bike_computer/features/more/more_screen.dart';
import 'package:bike_computer/features/settings/sensors_screen.dart';

void main() {
  testWidgets('internal app hub searches and opens a working sensor screen', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: MoreScreen()));
    expect(find.text('VELO-functies'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Sensoren');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(Card, 'Sensoren'), findsOneWidget);
    expect(find.text('Standaardlauncher instellen'), findsNothing);
    await tester.tap(find.widgetWithText(Card, 'Sensoren'));
    await tester.pumpAndSettle();
    expect(find.byType(SensorsScreen), findsOneWidget);
    expect(find.text('Scan sensoren'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
