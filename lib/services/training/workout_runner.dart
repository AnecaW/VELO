import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:bike_computer/services/training/training_generator.dart';
import 'package:bike_computer/services/bluetooth/ble_sensor_manager.dart';
import 'package:bike_computer/models/sensor_models.dart';

class WorkoutRunner extends ChangeNotifier {
  final TrainingStore store;
  final BleSensorManager sensors;
  final DateTime Function() now;
  WorkoutRunner(this.store, this.sensors, {DateTime Function()? now})
    : now = now ?? DateTime.now;
  TrainingPlan? plan;
  int index = 0, elapsed = 0, activeSeconds = 0;
  bool paused = false, complete = false, skipped = false;
  String? rideId, error;
  DateTime? started, _last;
  Timer? _timer;
  StreamSubscription<SensorReading>? _sensor;
  final List<Map<String, dynamic>> measurements = [];
  final Map<String, SensorReading> _latest = {};
  Future<void> _writes = Future.value();
  bool _disposed = false;
  TrainingStep? get current =>
      plan == null || complete ? null : plan!.steps[index];
  int get remaining => current == null ? 0 : current!.seconds - elapsed;
  SensorReading? reading(SensorType type) {
    final r = _latest[type.name];
    return r != null && now().difference(r.timestamp).inSeconds <= 10
        ? r
        : null;
  }

  Future<void> start(TrainingPlan value, {String? ride}) async {
    if (plan != null && !complete) {
      throw StateError('Beëindig eerst de actieve training');
    }
    value.validate();
    plan = value;
    index = 0;
    elapsed = 0;
    activeSeconds = 0;
    paused = false;
    complete = false;
    skipped = false;
    started = now();
    _last = started;
    rideId = ride;
    measurements.clear();
    _latest.clear();
    await _sensor?.cancel();
    _sensor = sensors.sensorDataStream.listen((r) {
      _latest[r.type.name] = r;
    });
    await _save('active');
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
    notifyListeners();
  }

  void tick() {
    if (plan == null || complete) return;
    final time = now(), delta = time.difference(_last!).inSeconds;
    if (delta <= 0) return;
    _last = _last!.add(Duration(seconds: delta));
    if (!paused) {
      var left = delta;
      while (left > 0 && !complete) {
        final use = left < remaining ? left : remaining;
        elapsed += use;
        activeSeconds += use;
        left -= use;
        if (elapsed == current!.seconds) {
          index++;
          elapsed = 0;
          if (index == plan!.steps.length) complete = true;
        }
      }
    }
    if (!paused && activeSeconds % 5 == 0) {
      for (final r in _latest.values) {
        if (time.difference(r.timestamp).inSeconds <= 10) {
          measurements.add({
            'time': time.toUtc().toIso8601String(),
            'type': r.type.name,
            'value': r.value,
            'step': index,
          });
        }
      }
      _save(complete ? 'completed' : 'active');
    }
    if (complete) {
      _timer?.cancel();
      _sensor?.cancel();
      _save(skipped ? 'completed-with-skips' : 'completed');
    }
    notifyListeners();
  }

  void toggle() {
    tick();
    paused = !paused;
    notifyListeners();
    _save('active');
  }

  void skip() {
    if (current == null) return;
    skipped = true;
    index++;
    elapsed = 0;
    if (index == plan!.steps.length) {
      complete = true;
      _timer?.cancel();
      _sensor?.cancel();
      _save('completed-with-skips');
    }
    notifyListeners();
  }

  Future<void> stop() async {
    tick();
    complete = true;
    _timer?.cancel();
    await _sensor?.cancel();
    await _save('stopped');
    notifyListeners();
  }

  Future<void> _save(String status) {
    final p = plan;
    if (p == null) return Future.value();
    final resultId = 'result-${started!.microsecondsSinceEpoch}';
    final raw = jsonEncode({
      'id': 'result-${started!.microsecondsSinceEpoch}',
      'planId': p.id,
      'plan': p.encode(),
      'name': p.name,
      'started': started!.toIso8601String(),
      'status': status,
      'seconds': activeSeconds,
      'step': index,
      'rideId': rideId,
      'measurements': measurements,
    });
    final task = _writes.then(
      (_) => store.db.putDocument('training-results', resultId, raw),
    );
    _writes = task.catchError((Object e) {
      error = 'Resultaat opslaan mislukt: $e';
      if (!_disposed) notifyListeners();
    });
    return task;
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _sensor?.cancel();
    super.dispose();
  }
}
