import 'dart:io';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bike_computer/database/bike_computer_database.dart';
import 'package:bike_computer/services/training/training_generator.dart';
import 'package:bike_computer/services/training/workout_runner.dart';
import 'package:bike_computer/services/bluetooth/ble_sensor_manager.dart';
import 'package:bike_computer/services/navigation/map_provider.dart';

void main() {
  for (final minutes in [10, 15, 30, 45, 60, 120, 240]) {
    test('generator exact duration for $minutes minutes', () async {
      final p = await LocalTrainingGenerator().generate(
        TrainingProfile(
          minutes: minutes,
          goal: 'Intervallen',
          preference: 'Intervallen',
        ),
      );
      expect(p.seconds, minutes * 60);
      expect(p.steps.first.name, 'Opwarming');
      expect(p.steps.last.name, 'Cooling-down');
      expect(p.steps.every((s) => s.seconds > 0), true);
      p.validate();
    });
  }
  test('unknown FTP never creates invented wattage or workload', () async {
    final p = await LocalTrainingGenerator().generate(const TrainingProfile());
    expect(p.ftp, isNull);
    expect(p.estimatedTss, isNull);
    expect(p.steps.every((s) => s.ftpFraction == null), true);
  });
  test('provided FTP creates bounded targets and estimated workload', () async {
    final p = await LocalTrainingGenerator().generate(
      const TrainingProfile(ftp: 220, preference: 'Intervallen'),
    );
    expect(p.ftp, 220);
    expect(p.estimatedTss, greaterThan(0));
    expect(p.steps.every((s) => s.ftpFraction! <= 1.3), true);
  });
  test('beginner efforts remain within selected conservative bounds', () async {
    final p = await LocalTrainingGenerator().generate(
      const TrainingProfile(intensity: 9, preference: 'Intervallen'),
    );
    expect(p.steps.every((s) => s.rpe <= 7), true);
  });
  test(
    'recovery preference creates recovery rather than hard intervals',
    () async {
      final p = await LocalTrainingGenerator().generate(
        const TrainingProfile(preference: 'Herstel', intensity: 8),
      );
      expect(p.steps.every((s) => s.rpe <= 2), true);
    },
  );
  test('invalid profile and incomplete personal goal are rejected', () async {
    for (final p in [
      const TrainingProfile(minutes: 0),
      const TrainingProfile(ftp: -1),
      const TrainingProfile(days: 7),
      const TrainingProfile(goal: 'Persoonlijk'),
    ]) {
      await expectLater(
        LocalTrainingGenerator().generate(p),
        throwsFormatException,
      );
    }
  });
  test('AI or imported plans cannot bypass step validation', () {
    final p = TrainingPlan(
      id: 'invalid',
      name: 'Invalid',
      goal: 'AI',
      steps: [const TrainingStep('bad', -1, 20, ftpFraction: 1.5)],
      created: DateTime(2026),
    );
    expect(p.validate, throwsFormatException);
  });
  test('training profiles and plans survive SQLite close and reopen', () async {
    final dir = await Directory.systemTemp.createTemp('training-persistence');
    final file = File('${dir.path}/db.sqlite');
    var db = BikeComputerDatabase(executor: NativeDatabase(file));
    var store = TrainingStore(db);
    const profile = TrainingProfile(ftp: 230, goal: 'Tempo');
    await store.profile(profile);
    final p = await LocalTrainingGenerator().generate(profile);
    await store.save(p.copy(scheduled: '2026-11-03'));
    await db.close();
    db = BikeComputerDatabase(executor: NativeDatabase(file));
    store = TrainingStore(db);
    expect((await store.loadProfile()).ftp, 230);
    expect((await store.plans()).single.seconds, p.seconds);
    expect((await store.plans()).single.scheduled, '2026-11-03');
    await db.close();
    await dir.delete(recursive: true);
  });
  test(
    'execution advances accurately, pauses, and persists true completion',
    () async {
      final db = BikeComputerDatabase(executor: NativeDatabase.memory());
      final sensors = BleSensorManager();
      var clock = DateTime.utc(2026);
      final runner = WorkoutRunner(
        TrainingStore(db),
        sensors,
        now: () => clock,
      );
      final p = TrainingPlan(
        id: 'run',
        name: 'Timed test',
        goal: 'Test',
        steps: [const TrainingStep('a', 30, 2), const TrainingStep('b', 30, 3)],
        created: clock,
      );
      await runner.start(p);
      clock = clock.add(const Duration(seconds: 20));
      runner.tick();
      expect(runner.remaining, 10);
      runner.toggle();
      clock = clock.add(const Duration(seconds: 20));
      runner.tick();
      expect(runner.activeSeconds, 20);
      runner.toggle();
      clock = clock.add(const Duration(seconds: 40));
      runner.tick();
      expect(runner.complete, true);
      await Future<void>.delayed(Duration.zero);
      final results = await db.documents('training-results');
      final row = jsonDecode(results.values.single);
      expect(row['seconds'], 60);
      expect(row['status'], 'completed');
      expect(row['measurements'], isEmpty);
      runner.dispose();
      sensors.dispose();
      await db.close();
    },
  );
  test('offline tile estimate and provider policy reject oversized areas', () {
    const small = DownloadBounds(50.84, 4.34, 50.85, 4.35, 10, 12);
    small.validate();
    expect(small.tiles, greaterThan(0));
    expect(
      () => const DownloadBounds(-80, -170, 80, 170, 1, 16).validate(),
      throwsFormatException,
    );
    expect(
      () => const DownloadBounds(51, 5, 50, 4, 10, 12).validate(),
      throwsFormatException,
    );
  });
}
