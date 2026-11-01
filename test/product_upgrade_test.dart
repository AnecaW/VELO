import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:bike_computer/widgets/route_map.dart';
import 'package:bike_computer/core/runtime.dart';
import 'package:bike_computer/core/settings.dart';
import 'package:bike_computer/database/bike_computer_database.dart';
import 'package:bike_computer/models/gps_models.dart';
import 'package:bike_computer/models/ride_session.dart';
import 'package:bike_computer/services/gps/gps_service.dart';
import 'package:bike_computer/services/bluetooth/ble_sensor_manager.dart';
import 'package:bike_computer/services/recording/ride_controller.dart';
import 'package:bike_computer/features/profiles/cubits/activity_profile_cubit.dart';
import 'package:bike_computer/services/training/training_generator.dart';
import 'package:bike_computer/services/storage/backup_service.dart';

class ControllerGps implements GPSService {
  final events = StreamController<GPSLocation>.broadcast(sync: true);
  int starts = 0, stops = 0;
  @override
  Stream<GPSLocation> get locationStream => events.stream;
  @override
  Future<void> startListening() async {
    starts++;
  }

  @override
  Future<void> stopListening() async {
    stops++;
  }

  @override
  Future<bool> isAvailable() async => true;
  @override
  GPSLocation? getLastLocation() => null;
}

void main() {
  testWidgets(
    'vector GPS updates never touch the unattached raster controller',
    (tester) async {
      await tester.runAsync(() => Runtime.settings.set('mapEngine', 'vector'));
      await tester.pumpWidget(const MaterialApp(home: RouteMap()));
      await tester.pumpWidget(
        const MaterialApp(home: RouteMap(position: LatLng(51, 4))),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test('application controller preserves recording while views detach and reattach', () async {
    final db = BikeComputerDatabase(executor: NativeDatabase.memory()),
        gps = ControllerGps(),
        sensors = BleSensorManager();
    final c = RideController(db, AppSettings(db), sensors, injectedGps: gps);
    await c.initialize();
    await c.start();
    final original = c.service;
    var received = 0;
    void view() {
      received++;
    }

    c.addListener(view);
    gps.events.add(
      GPSLocation(
        latitude: 51,
        longitude: 4,
        altitude: 10,
        accuracy: 5,
        speed: 5,
        heading: 0,
        timestamp: DateTime.now(),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    c.removeListener(view);
    expect(c.session.state, RideState.recording);
    expect(gps.stops, 0);
    c.addListener(view);
    expect(identical(c.service, original), true);
    await c.service.pauseRecording();
    expect(c.session.state, RideState.paused);
    expect(received, greaterThan(0));
    await c.service.stopRecording();
    await c.writes;
    c.dispose();
    sensors.dispose();
    await gps.events.close();
    await db.close();
  });
  test('training data participates in backup roundtrip', () async {
    final db = BikeComputerDatabase(executor: NativeDatabase.memory());
    final store = TrainingStore(db), backup = BackupService(db);
    final plan = await LocalTrainingGenerator().generate(
      const TrainingProfile(),
    );
    await store.save(plan);
    await store.profile(const TrainingProfile());
    final archive = await backup.export();
    await db.removeDocument('training-plans', plan.id);
    await backup.restore(archive);
    expect((await store.plans()).single.seconds, 2700);
    expect((await store.loadProfile()).minutes, 45);
    await db.close();
  });
  test('edited activity profiles survive a new cubit instance', () async {
    final db = BikeComputerDatabase(executor: NativeDatabase.memory());
    Runtime.configure(db);
    final c = ActivityProfileCubit();
    await c.loadProfiles();
    final p = c.state.profiles.first.copyWith(
      name: 'My road',
      autoPauseEnabled: false,
    );
    await c.updateProfile(p);
    await c.close();
    final restored = ActivityProfileCubit();
    await restored.loadProfiles();
    expect(restored.state.profiles.first.name, 'My road');
    expect(restored.state.profiles.first.autoPauseEnabled, false);
    await restored.close();
    await db.close();
  });
}
