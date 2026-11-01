import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bike_computer/features/settings/settings_screen.dart';

void main() {
  testWidgets(
    'navigation settings disclose online dependency and actual controls',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
      await tester.scrollUntilVisible(
        find.text('Navigatie'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Navigatie'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Navigatie'));
      await tester.pumpAndSettle();
      expect(find.text('Navigatie-opties'), findsOneWidget);
      expect(find.text('Automatisch herberekenen'), findsOneWidget);
      expect(find.text('Gesproken aanwijzingen'), findsOneWidget);
    },
  );
  testWidgets('GPS settings expose recording filters', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.scrollUntilVisible(
      find.text('GPS en opname'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('GPS en opname'));
    await tester.pumpAndSettle();
    expect(find.text('Hoge GPS-nauwkeurigheid'), findsOneWidget);
  });
}
