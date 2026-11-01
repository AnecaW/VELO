import 'dart:convert';
import 'dart:math' as math;

import 'package:bike_computer/database/bike_computer_database.dart';

class TrainingProfile {
  final String goal, level, environment, preference, custom;
  final int minutes, days, intensity;
  final List<int> weekdays;
  final double? ftp;
  final int? hrLow, hrHigh;
  final bool powerSensor, heartSensor;
  const TrainingProfile({
    this.goal = 'Conditie',
    this.level = 'Beginner',
    this.environment = 'Buiten',
    this.preference = 'Duur',
    this.custom = '',
    this.minutes = 45,
    this.days = 3,
    this.intensity = 5,
    this.weekdays = const [1, 3, 6],
    this.ftp,
    this.hrLow,
    this.hrHigh,
    this.powerSensor = false,
    this.heartSensor = false,
  });
  Map<String, dynamic> toJson() => {
    'goal': goal,
    'level': level,
    'environment': environment,
    'preference': preference,
    'custom': custom,
    'minutes': minutes,
    'days': days,
    'intensity': intensity,
    'weekdays': weekdays,
    'ftp': ftp,
    'hrLow': hrLow,
    'hrHigh': hrHigh,
    'powerSensor': powerSensor,
    'heartSensor': heartSensor,
  };
  factory TrainingProfile.fromJson(Map<String, dynamic> j) => TrainingProfile(
    goal: j['goal'],
    level: j['level'],
    environment: j['environment'],
    preference: j['preference'],
    custom: j['custom'] ?? '',
    minutes: j['minutes'],
    days: j['days'],
    intensity: j['intensity'],
    weekdays: (j['weekdays'] as List).cast<int>(),
    ftp: (j['ftp'] as num?)?.toDouble(),
    hrLow: j['hrLow'],
    hrHigh: j['hrHigh'],
    powerSensor: j['powerSensor'] ?? false,
    heartSensor: j['heartSensor'] ?? false,
  );
  void validate() {
    if (goal == 'Persoonlijk' && custom.trim().isEmpty) {
      throw const FormatException('Vul je persoonlijke doel in');
    }
    if (weekdays.toSet().length < days) {
      throw const FormatException(
        'Selecteer minstens zoveel beschikbare dagen als trainingsdagen',
      );
    }
    if (minutes < 10 ||
        minutes > 240 ||
        days < 1 ||
        days > 7 ||
        intensity < 1 ||
        intensity > 9 ||
        weekdays.any((d) => d < 1 || d > 7) ||
        (ftp != null && (!ftp!.isFinite || ftp! < 30 || ftp! > 1000)) ||
        (hrLow != null &&
            hrHigh != null &&
            (hrLow! < 30 || hrHigh! > 240 || hrLow! >= hrHigh!))) {
      throw const FormatException(
        'Controleer tijd, dagen, intensiteit, FTP en hartslagzones',
      );
    }
  }
}

class TrainingStep {
  final String name;
  final int seconds, rpe;
  final double? ftpFraction;
  final int? hrLow, hrHigh, cadence;
  const TrainingStep(
    this.name,
    this.seconds,
    this.rpe, {
    this.ftpFraction,
    this.hrLow,
    this.hrHigh,
    this.cadence,
  });
  Map<String, dynamic> toJson() => {
    'name': name,
    'seconds': seconds,
    'rpe': rpe,
    'ftpFraction': ftpFraction,
    'hrLow': hrLow,
    'hrHigh': hrHigh,
    'cadence': cadence,
  };
  factory TrainingStep.fromJson(Map<String, dynamic> j) => TrainingStep(
    j['name'],
    j['seconds'],
    j['rpe'],
    ftpFraction: (j['ftpFraction'] as num?)?.toDouble(),
    hrLow: j['hrLow'],
    hrHigh: j['hrHigh'],
    cadence: j['cadence'],
  );
}

class TrainingPlan {
  final String id, name, goal;
  final List<TrainingStep> steps;
  final double? ftp;
  final DateTime created;
  final String? scheduled;
  const TrainingPlan({
    required this.id,
    required this.name,
    required this.goal,
    required this.steps,
    required this.created,
    this.ftp,
    this.scheduled,
  });
  int get seconds => steps.fold(0, (a, s) => a + s.seconds);
  double? get estimatedTss => ftp == null
      ? null
      : steps.fold<double>(
          0.0,
          (v, s) =>
              v + s.seconds / 3600 * math.pow(s.ftpFraction ?? 0, 2) * 100,
        );
  TrainingPlan copy({
    String? id,
    String? name,
    List<TrainingStep>? steps,
    String? scheduled,
  }) => TrainingPlan(
    id: id ?? this.id,
    name: name ?? this.name,
    goal: goal,
    steps: steps ?? this.steps,
    created: created,
    ftp: ftp,
    scheduled: scheduled ?? this.scheduled,
  );
  void validate() {
    if (name.trim().isEmpty ||
        steps.isEmpty ||
        seconds < 60 ||
        seconds > 14400 ||
        steps.any(
          (s) =>
              s.seconds <= 0 ||
              s.rpe < 1 ||
              s.rpe > 10 ||
              (s.ftpFraction != null &&
                  (ftp == null ||
                      !s.ftpFraction!.isFinite ||
                      s.ftpFraction! < .2 ||
                      s.ftpFraction! > 1.3)) ||
              (s.hrLow != null && (s.hrHigh == null || s.hrLow! >= s.hrHigh!)),
        )) {
      throw const FormatException(
        'Ongeldige trainingsstappen of ontbrekende FTP',
      );
    }
  }

  String encode() => jsonEncode({
    'id': id,
    'name': name,
    'goal': goal,
    'steps': steps.map((s) => s.toJson()).toList(),
    'ftp': ftp,
    'created': created.toIso8601String(),
    'scheduled': scheduled,
  });
  factory TrainingPlan.decode(String raw) {
    final j = jsonDecode(raw);
    return TrainingPlan(
      id: j['id'],
      name: j['name'],
      goal: j['goal'],
      steps: (j['steps'] as List)
          .map((s) => TrainingStep.fromJson(Map<String, dynamic>.from(s)))
          .toList(),
      created: DateTime.parse(j['created']),
      ftp: (j['ftp'] as num?)?.toDouble(),
      scheduled: j['scheduled'],
    );
  }
}

abstract interface class TrainingGenerator {
  Future<TrainingPlan> generate(TrainingProfile profile);
}

/// An optional AI adapter must implement this interface and is validated by the store.
abstract interface class AiTrainingProvider implements TrainingGenerator {}

class LocalTrainingGenerator implements TrainingGenerator {
  final DateTime Function() now;
  LocalTrainingGenerator({DateTime Function()? now})
    : now = now ?? DateTime.now;
  @override
  Future<TrainingPlan> generate(TrainingProfile p) async {
    p.validate();
    final total = p.minutes * 60,
        warm = math.min(600, total ~/ 5),
        cool = math.min(600, total ~/ 6),
        body = total - warm - cool;
    TrainingStep step(
      String name,
      int seconds,
      int rpe, {
      double? fraction,
      int? cadence,
    }) => TrainingStep(
      name,
      seconds,
      rpe,
      ftpFraction: p.ftp == null ? null : fraction,
      hrLow: p.heartSensor ? p.hrLow : null,
      hrHigh: p.heartSensor ? p.hrHigh : null,
      cadence: cadence,
    );
    final steps = [step('Opwarming', warm, 2, fraction: .5)];
    final interval =
        p.preference == 'Intervallen' ||
        ['Intervallen', 'Klimmen', 'Tempo'].contains(p.goal);
    if (interval) {
      final repetitions = math.min(
        p.level == 'Beginner' ? 4 : 6,
        math.max(2, body ~/ 180),
      );
      final pair = body ~/ repetitions, work = pair * 2 ~/ 3;
      var allocated = 0;
      for (var i = 0; i < repetitions; i++) {
        final recovery = i == repetitions - 1
            ? body - allocated - work
            : pair - work;
        steps.add(
          step(
            'Werk ${i + 1}/$repetitions',
            work,
            p.intensity.clamp(4, p.level == 'Beginner' ? 7 : 9),
            fraction: p.goal == 'Tempo' ? .85 : 1.05,
            cadence: p.goal == 'Cadans' ? 95 : null,
          ),
        );
        steps.add(step('Herstel', recovery, 2, fraction: .45));
        allocated += work + recovery;
      }
    } else {
      final recovery = p.goal == 'Herstel' || p.preference == 'Herstel';
      steps.add(
        step(
          recovery ? 'Rustig herstel' : 'Duurblok',
          body,
          recovery ? 2 : p.intensity.clamp(2, 6),
          fraction: recovery ? .45 : .65,
          cadence: p.goal == 'Cadans' ? 90 : null,
        ),
      );
    }
    steps.add(step('Cooling-down', cool, 1, fraction: .4));
    final t = now();
    final plan = TrainingPlan(
      id: 'training-${t.microsecondsSinceEpoch}',
      name: '${p.goal} · ${p.minutes} min',
      goal: p.goal == 'Persoonlijk' ? p.custom : p.goal,
      steps: steps,
      ftp: p.ftp,
      created: t,
    );
    plan.validate();
    if (plan.seconds != total) throw StateError('Trainingsduur klopt niet');
    return plan;
  }
}

class TrainingStore {
  final BikeComputerDatabase db;
  TrainingStore(this.db);
  Future<void> save(TrainingPlan plan) async {
    plan.validate();
    await db.putDocument('training-plans', plan.id, plan.encode());
  }

  Future<List<TrainingPlan>> plans() async =>
      (await db.documents('training-plans')).values
          .map(TrainingPlan.decode)
          .toList()
        ..sort((a, b) => b.created.compareTo(a.created));
  Future<void> profile(TrainingProfile p) async {
    p.validate();
    await db.putDocument('training-profile', 'current', jsonEncode(p.toJson()));
  }

  Future<TrainingProfile> loadProfile() async {
    final raw = await db.getDocument('training-profile', 'current');
    return raw == null
        ? const TrainingProfile()
        : TrainingProfile.fromJson(jsonDecode(raw));
  }
}
