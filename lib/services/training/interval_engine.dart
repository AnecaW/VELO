class WorkoutStep {
  final String name;
  final int seconds;
  final double ftpFraction;
  const WorkoutStep(this.name, this.seconds, this.ftpFraction);
}

class IntervalEngine {
  final List<WorkoutStep> steps;
  int index = 0, elapsed = 0;
  bool paused = false;
  IntervalEngine(this.steps) {
    if (steps.isEmpty || steps.any((s) => s.seconds <= 0)) {
      throw ArgumentError('Invalid workout');
    }
  }
  bool get complete => index >= steps.length;
  WorkoutStep? get current => complete ? null : steps[index];
  int get remaining => complete ? 0 : steps[index].seconds - elapsed;
  void advance(int seconds) {
    if (seconds < 0) throw ArgumentError('Negative time');
    if (paused) return;
    while (seconds > 0 && !complete) {
      if (seconds >= remaining) {
        seconds -= remaining;
        index++;
        elapsed = 0;
      } else {
        elapsed += seconds;
        seconds = 0;
      }
    }
  }

  void skip() {
    if (!complete) {
      index++;
      elapsed = 0;
    }
  }

  static int powerZone(double watts, double ftp) {
    if (!watts.isFinite || !ftp.isFinite || watts < 0 || ftp <= 0) {
      throw ArgumentError('Invalid power/FTP');
    }
    final ratio = watts / ftp;
    for (var i = 0; i < 6; i++) {
      if (ratio <= [.55, .75, .90, 1.05, 1.20, 1.50][i]) return i + 1;
    }
    return 7;
  }

  static List<WorkoutStep> forPlan(String id) {
    if (id == 'interval') {
      return [
        const WorkoutStep('Warm-up', 600, .55),
        for (var i = 0; i < 5; i++) ...[
          const WorkoutStep('Effort', 60, 1.20),
          const WorkoutStep('Recovery', 120, .50),
        ],
        const WorkoutStep('Cool-down', 600, .45),
      ];
    }
    if (id == 'tempo') {
      return const [
        WorkoutStep('Warm-up', 600, .55),
        WorkoutStep('Tempo', 1500, .85),
        WorkoutStep('Cool-down', 600, .50),
      ];
    }
    return const [WorkoutStep('Easy spin', 3000, .50)];
  }
}
