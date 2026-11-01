import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bike_computer/features/home/home_screen.dart';

void main() {
  testWidgets(
    'Home screen lets the user change the selected activity profile',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

      final mtbChip = find.byKey(const ValueKey('profile-chip-mtb_default'));
      expect(mtbChip, findsOneWidget);

      await tester.tap(mtbChip);
      await tester.pumpAndSettle();

      expect(find.text('MTB'), findsWidgets);
    },
  );
}
