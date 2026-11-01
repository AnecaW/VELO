import 'dart:async';

import 'package:flutter/material.dart';
import 'package:bike_computer/core/runtime.dart';
import 'package:bike_computer/services/training/interval_engine.dart';
import 'package:bike_computer/models/sensor_models.dart';

class WorkoutScreen extends StatefulWidget {
  final String plan;
  const WorkoutScreen({super.key, required this.plan});
  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  late IntervalEngine engine;
  Timer? timer;
  DateTime last = DateTime.now();
  StreamSubscription<SensorReading>? sensor;
  double? watts;
  DateTime? readingTime;
  @override
  void initState() {
    super.initState();
    engine = IntervalEngine(IntervalEngine.forPlan(widget.plan));
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      final seconds = now.difference(last).inSeconds;
      if (seconds > 0) {
        last = last.add(Duration(seconds: seconds));
        engine.advance(seconds);
        if (mounted) setState(() {});
      }
    });
    sensor = Runtime.sensors.sensorDataStream.listen((r) {
      if (r.type == SensorType.power && mounted) {
        setState(() {
          watts = r.value;
          readingTime = r.timestamp;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final step = engine.current;
    final ftp = Runtime.settings.value('ftp', 250.0);
    final fresh =
        readingTime != null &&
        DateTime.now().difference(readingTime!).inSeconds < 10;
    return Scaffold(
      appBar: AppBar(title: const Text('INTERVAL TRAINING')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            step?.name ?? 'Training voltooid',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 24),
          Text(
            '${engine.remaining ~/ 60}:${(engine.remaining % 60).toString().padLeft(2, '0')}',
            style: Theme.of(context).textTheme.displayLarge,
          ),
          if (step != null)
            Text(
              'Doel: ${(step.ftpFraction * ftp).round()} W · ${(step.ftpFraction * 100).round()}% FTP',
            ),
          Text(
            fresh
                ? '${watts!.round()} W · zone ${IntervalEngine.powerZone(watts!, ftp)}'
                : 'Geen actuele vermogensmeting',
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: engine.complete
                ? null
                : () => setState(() => engine.paused = !engine.paused),
            child: Text(engine.paused ? 'Hervat' : 'Pauze'),
          ),
          OutlinedButton(
            onPressed: engine.complete
                ? null
                : () => setState(() => engine.skip()),
            child: const Text('Volgend interval'),
          ),
          const Text(
            'Deze trainingstimer registreert geen GPS-rit en bestuurt geen trainer. Vermogensdoelen zijn gebaseerd op je ingestelde FTP.',
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    sensor?.cancel();
    super.dispose();
  }
}
