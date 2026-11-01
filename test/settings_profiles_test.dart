import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bike_computer/features/settings/settings_screen.dart';

void main() {
  testWidgets('Settings profile editor shows selectable activity profiles', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));

    await tester.scrollUntilVisible(
      find.text('Activiteitprofielen'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Activiteitprofielen'));
    await tester.pumpAndSettle();

    expect(find.text('Activiteitprofielen'), findsOneWidget);
    expect(find.text('Road'), findsWidgets);
    expect(find.text('MTB'), findsWidgets);
  });
}
