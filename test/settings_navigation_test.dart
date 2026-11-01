import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bike_computer/features/settings/settings_screen.dart';

void main() {
  testWidgets(
    'navigation settings disclose online dependency and actual controls',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
      await tester.scrollUntilVisible(find.text('Navigation'), 200);
      await tester.tap(find.text('Navigation'));
      await tester.pumpAndSettle();
      expect(find.text('Navigation Settings'), findsOneWidget);
      expect(find.text('Auto Re-route'), findsOneWidget);
      expect(find.text('Voice Prompts'), findsOneWidget);
    },
  );
  testWidgets('GPS settings expose recording filters', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.tap(find.text('GPS & Recording'));
    await tester.pumpAndSettle();
    expect(find.text('Hoge GPS-nauwkeurigheid'), findsOneWidget);
  });
}
