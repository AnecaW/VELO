import 'package:flutter_test/flutter_test.dart';
import 'package:bike_computer/features/ride/cubits/ride_session_cubit.dart';
import 'package:bike_computer/models/sensor_models.dart';
import 'package:bike_computer/services/bluetooth/ble_sensor_manager.dart';
import 'package:bike_computer/services/gps/gps_service.dart';
import 'package:bike_computer/services/ride/ride_recording_service.dart';

void main() {
  group('BleSensorManager', () {
    test('scans and discovers supported sensors', () async {
      final manager = BleSensorManager(simulate: true);

      final sensors = await manager.scanForSensors();

      expect(sensors, isNotEmpty);
      expect(
        sensors.any((sensor) => sensor.type == SensorType.heartRate),
        isTrue,
      );
      expect(
        sensors.any((sensor) => sensor.type == SensorType.cadence),
        isTrue,
      );
      expect(sensors.any((sensor) => sensor.type == SensorType.power), isTrue);
    });

    test('connects sensors and exposes active connections', () async {
      final manager = BleSensorManager(simulate: true);
      final sensors = await manager.scanForSensors();

      final target = sensors.first;
      await manager.connectSensor(target.id);

      expect(manager.isConnected(target.id), isTrue);
      expect(manager.connectedSensors.length, greaterThanOrEqualTo(1));
    });

    test('ride session updates from connected BLE sensors', () async {
      final manager = BleSensorManager(simulate: true);
      final service = RideRecordingService(
        gpsService: MockGPSService(),
        bleSensorManager: manager,
      );

      await service.initializeRide();
      await service.startRecording();
      await manager.connectSensor('hr-001');
      await manager.connectSensor('cad-001');
      await manager.connectSensor('pow-001');

      expect(service.currentSession.currentHeartRate, 156.0);
      expect(service.currentSession.currentCadence, 92.0);
      expect(service.currentSession.currentPower, 248.0);

      service.dispose();
      manager.dispose();
    });

    test(
      'ride session cubit wires simulated sensors into the active ride',
      () async {
        final manager = BleSensorManager(simulate: true);
        final cubit = RideSessionCubit(
          gpsService: MockGPSService(),
          bleSensorManager: manager,
        );

        await cubit.initializeRide();
        await cubit.startRecording();
        await manager.connectSensor('hr-001');
        await manager.connectSensor('cad-001');
        await manager.connectSensor('pow-001');
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(cubit.state.session.currentHeartRate, 156.0);
        expect(cubit.state.session.currentCadence, 92.0);
        expect(cubit.state.session.currentPower, 248.0);

        await cubit.close();
        manager.dispose();
      },
    );
  });
}
