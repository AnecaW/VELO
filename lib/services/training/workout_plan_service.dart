class WorkoutPlan {
  final String id;
  final String name;
  final String focus;
  final int durationMinutes;
  final int intensity;
  final String description;

  const WorkoutPlan({
    required this.id,
    required this.name,
    required this.focus,
    required this.durationMinutes,
    required this.intensity,
    required this.description,
  });
}

class WorkoutPlanService {
  static final List<WorkoutPlan> standardPlans = [
    const WorkoutPlan(
      id: 'tempo',
      name: 'Tempo Ride',
      focus: 'Threshold',
      durationMinutes: 45,
      intensity: 7,
      description: 'Steady effort with controlled power and cadence.',
    ),
    const WorkoutPlan(
      id: 'interval',
      name: 'Interval Blast',
      focus: 'VO2 Max',
      durationMinutes: 35,
      intensity: 9,
      description: 'Short hard efforts with active recovery blocks.',
    ),
    const WorkoutPlan(
      id: 'recovery',
      name: 'Recovery Spin',
      focus: 'Endurance',
      durationMinutes: 50,
      intensity: 4,
      description: 'Light aerobic effort to recover and rebuild.',
    ),
  ];

  static WorkoutPlan? getPlan(String id) {
    return standardPlans.where((plan) => plan.id == id).firstOrNull;
  }

  static double estimateCalories(WorkoutPlan plan, {required double weightKg}) {
    if (weightKg <= 0) {
      throw ArgumentError.value(
        weightKg,
        'weightKg',
        'Weight must be greater than zero.',
      );
    }

    final baseBurn = plan.durationMinutes * 5.5;
    final intensityBoost = plan.intensity * 6.5;
    return (baseBurn + intensityBoost) * (weightKg / 70.0);
  }
}

extension _ListX<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
