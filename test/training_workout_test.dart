import 'package:bike_computer/core/runtime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bike_computer/services/training/workout_plan_service.dart';

import 'package:flutter/material.dart';
import 'package:bike_computer/features/training/training_screen.dart';

void main() {
  group('WorkoutPlanService', () {
    test('returns default training plans with valid metadata', () {
      final plans = WorkoutPlanService.standardPlans;

      expect(plans, isNotEmpty);
      expect(plans.any((plan) => plan.id == 'tempo'), isTrue);
      expect(plans.every((plan) => plan.durationMinutes > 0), isTrue);
      expect(plans.every((plan) => plan.intensity > 0), isTrue);
    });

    test('calculates a realistic effort estimate for a session', () {
      final plan = WorkoutPlanService.getPlan('interval')!;
      final estimate = WorkoutPlanService.estimateCalories(plan, weightKg: 72);

      expect(estimate, greaterThan(0));
      expect(
        estimate,
        greaterThanOrEqualTo((plan.durationMinutes * 6).toDouble()),
      );
    });
  });

  testWidgets(
    'training center generates a real editable local plan without sample results',
    (tester) async {
      await tester.runAsync(() async {
        await Runtime.database.documents('training-plans');
      });
      await tester.pumpWidget(const MaterialApp(home: TrainingScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Tempo Ride'), findsNothing);
      expect(find.byKey(const ValueKey('generate-workout')), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('generate-workout')),
      );
      await tester.tap(find.byKey(const ValueKey('generate-workout')));
      await tester.pumpAndSettle();
      expect(find.text('Trainingsadvies'), findsOneWidget);
      expect(find.textContaining('Geen FTP ingesteld'), findsOneWidget);
      expect(find.text('Training opslaan'), findsOneWidget);
    },
  );
}
