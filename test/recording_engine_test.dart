import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:bike_computer/models/gps_models.dart';
import 'package:bike_computer/models/ride_session.dart';
import 'package:bike_computer/services/gps/gps_service.dart';
import 'package:bike_computer/services/ride/ride_recording_service.dart';
import 'package:bike_computer/services/ride/calculations.dart';
import 'package:bike_computer/services/bluetooth/ble_sensor_manager.dart';
import 'package:bike_computer/services/bluetooth/ble_decoder.dart';

class FakeGPS implements GPSService {
  final controller = StreamController<GPSLocation>.broadcast(sync: true);
  bool fail = false;
  @override
  Stream<GPSLocation> get locationStream => controller.stream;
  @override
  Future<void> startListening() async {
    if (fail) throw StateError('Permission denied');
  }

  @override
  Future<void> stopListening() async {}
  @override
  Future<bool> isAvailable() async => !fail;
  @override
  GPSLocation? getLastLocation() => null;
}

void main() {
  late FakeGPS gps;
  late RideRecordingService engine;
  late DateTime time;
  GPSLocation point({
    double lat = 51,
    double lon = 4,
    double accuracy = 5,
    double speed = 5,
    double altitude = 10,
  }) => GPSLocation(
    latitude: lat,
    longitude: lon,
    accuracy: accuracy,
    speed: speed,
    altitude: altitude,
    heading: 0,
    timestamp: time,
  );
  Future<void> start({bool auto = false}) async {
    engine = RideRecordingService(
      gpsService: gps,
      now: () => time,
      autoPause: auto,
    );
    await engine.initializeRide();
    await engine.startRecording();
  }

  setUp(() {
    gps = FakeGPS();
    time = DateTime.utc(2026, 10, 31);
  });
  tearDown(() async {
    engine.dispose();
    await gps.controller.close();
  });
  test('Haversine known one degree and zero distance', () async {
    await start();
    expect(
      DistanceCalculator.distanceInMeters(0, 0, 0, 1),
      closeTo(111195, 100),
    );
    expect(DistanceCalculator.distanceInMeters(51, 4, 51, 4), 0);
  });
  test('average uses moving time and handles zero', () async {
    await start();
    expect(SpeedCalculator.averageSpeed(10, const Duration(minutes: 30)), 20);
    expect(SpeedCalculator.averageSpeed(0, Duration.zero), 0);
  });
  test('normal ride records distance, speed, maximum and time', () async {
    await start();
    gps.controller.add(point());
    time = time.add(const Duration(seconds: 5));
    gps.controller.add(point(lon: 4.0003, speed: 6));
    expect(engine.currentSession.totalDistance, greaterThan(0.02));
    expect(engine.currentSession.maxSpeed, 21.6);
    expect(engine.currentSession.elapsedTime.inSeconds, 5);
    expect(engine.currentSession.movingTime.inSeconds, 5);
  });
  test('pause excludes moving time but total time continues', () async {
    await start();
    gps.controller.add(point());
    time = time.add(const Duration(seconds: 5));
    await engine.pauseRecording();
    time = time.add(const Duration(seconds: 10));
    engine.tick();
    expect(engine.currentSession.movingTime.inSeconds, 5);
    expect(engine.currentSession.elapsedTime.inSeconds, 15);
    expect(engine.currentSession.pausedTime.inSeconds, 10);
  });
  test('resume never bridges a paused GPS gap', () async {
    await start();
    gps.controller.add(point());
    time = time.add(const Duration(seconds: 3));
    await engine.pauseRecording();
    time = time.add(const Duration(minutes: 1));
    await engine.startRecording();
    gps.controller.add(point(lon: 5));
    expect(engine.currentSession.totalDistance, 0);
    expect(engine.currentSession.trackPoints.last.segmentStart, isTrue);
  });
  test(
    'automatic pause needs sustained low speed and automatically resumes',
    () async {
      await start(auto: true);
      gps.controller.add(point(speed: 0));
      time = time.add(const Duration(seconds: 6));
      gps.controller.add(point(speed: 0));
      expect(engine.currentSession.state, RideState.paused);
      time = time.add(const Duration(seconds: 1));
      gps.controller.add(point(speed: 5));
      expect(engine.currentSession.state, RideState.recording);
    },
  );
  test('manual pause never resumes automatically', () async {
    await start(auto: true);
    await engine.pauseRecording();
    gps.controller.add(point(speed: 8));
    expect(engine.currentSession.state, RideState.paused);
  });
  test('bad accuracy, NaN and out of range locations are filtered', () async {
    await start();
    gps.controller.add(point(accuracy: 500));
    gps.controller.add(point(lat: double.nan));
    gps.controller.add(point(lat: 100));
    expect(engine.currentSession.trackPoints, isEmpty);
  });
  test('unrealistic speed and GPS jumps are rejected', () async {
    await start();
    gps.controller.add(point());
    time = time.add(const Duration(seconds: 1));
    gps.controller.add(point(lon: 5));
    expect(engine.currentSession.trackPoints.length, 1);
    gps.controller.add(point(speed: 100));
    expect(engine.currentSession.maxSpeed, 18);
  });
  test('duplicate and negative timestamps do not add points', () async {
    await start();
    gps.controller.add(point());
    gps.controller.add(point());
    time = time.subtract(const Duration(seconds: 1));
    gps.controller.add(point());
    expect(engine.currentSession.trackPoints.length, 1);
  });
  test('standing GPS jitter does not add distance', () async {
    await start();
    gps.controller.add(point(speed: 0));
    time = time.add(const Duration(seconds: 2));
    gps.controller.add(point(lon: 4.00002, speed: 0));
    expect(engine.currentSession.totalDistance, 0);
  });
  test('GPS outage is not bridged', () async {
    await start();
    gps.controller.add(point());
    time = time.add(const Duration(seconds: 40));
    gps.controller.add(point(lon: 4.001));
    expect(engine.currentSession.totalDistance, 0);
  });
  test('GPS loss expires current speed and moving time', () async {
    await start();
    gps.controller.add(point());
    time = time.add(const Duration(seconds: 20));
    engine.tick();
    expect(engine.currentSession.currentSpeed, 0);
    expect(engine.currentSession.movingTime, Duration.zero);
  });
  test('height noise is filtered while sustained climb is counted', () async {
    await start();
    for (var i = 0; i < 10; i++) {
      time = time.add(const Duration(seconds: 5));
      gps.controller.add(point(lon: 4 + i * .0002, altitude: 10 + i * 2));
    }
    expect(engine.currentSession.totalElevationGain, greaterThan(5));
    expect(engine.currentSession.totalElevationGain, lessThan(20));
  });
  test('state machine rejects invalid transitions', () async {
    await start();
    await expectLater(engine.initializeRide(), throwsStateError);
    await expectLater(engine.startRecording(), throwsStateError);
    expect(() => engine.markAsSaved('bad'), throwsStateError);
    await engine.stopRecording();
    await expectLater(engine.pauseRecording(), throwsStateError);
    engine.markAsSaved('ok');
    expect(engine.currentSession.state, RideState.saved);
  });
  test('permission failure leaves ready and supports retry', () async {
    engine = RideRecordingService(gpsService: gps);
    await engine.initializeRide();
    gps.fail = true;
    await expectLater(engine.startRecording(), throwsStateError);
    expect(engine.currentSession.state, RideState.ready);
    gps.fail = false;
    await engine.startRecording();
    expect(engine.currentSession.isRecording, isTrue);
  });
  test(
    'crash recovery resumes paused with retained track and totals',
    () async {
      engine = RideRecordingService(gpsService: gps);
      engine.restore(
        const RideSession(
          state: RideState.recording,
          totalDistance: 12,
          movingTime: Duration(minutes: 20),
        ),
      );
      expect(engine.currentSession.state, RideState.paused);
      expect(engine.currentSession.totalDistance, 12);
      await engine.startRecording();
      expect(engine.currentSession.movingTime.inMinutes, 20);
    },
  );
  test('sensor loss clears stale values without stopping recording', () async {
    final manager = BleSensorManager(simulate: true);
    engine = RideRecordingService(
      gpsService: gps,
      bleSensorManager: manager,
      now: () => time,
    );
    await engine.initializeRide();
    await engine.startRecording();
    time = DateTime.now();
    await manager.connectSensor('hr-001');
    await Future<void>.delayed(Duration.zero);
    expect(engine.currentSession.currentHeartRate, 156);
    time = time.add(const Duration(seconds: 15));
    engine.tick();
    expect(engine.currentSession.currentHeartRate, isNull);
    expect(engine.currentSession.isRecording, isTrue);
    manager.dispose();
  });
  test('BLE decodes 8 and 16 bit HR', () async {
    await start();
    expect(BleDecoder.heartRate([0, 156]), 156);
    expect(BleDecoder.heartRate([1, 44, 1]), 300);
  });
  test('BLE power is a signed 16 bit measurement', () async {
    await start();
    expect(BleDecoder.power([0, 0, 250, 0]), 250);
    expect(BleDecoder.power([0, 0, 255, 255]), -1);
  });
  test('BLE crank cadence handles 16 bit rollover', () async {
    await start();
    final d = BleDecoder();
    expect(d.cadence([2, 255, 255, 0, 252]), isNull);
    expect(d.cadence([2, 0, 0, 0, 0]), 60);
  });
  test('malformed BLE packets throw FormatException', () async {
    await start();
    expect(() => BleDecoder.heartRate([1, 10]), throwsFormatException);
    expect(() => BleDecoder.power([0]), throwsFormatException);
    expect(() => BleDecoder().cadence([2]), throwsFormatException);
  });
}
