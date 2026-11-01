import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:bike_computer/services/bluetooth/ble_decoder.dart';

import 'dart:async';

import 'package:bike_computer/core/errors/exceptions.dart';
import 'package:bike_computer/models/sensor_models.dart';

/// BLE sensor manager for heart rate, cadence and power sensors.
class BleSensorManager {
  final bool simulate;
  final Map<String, BluetoothDevice> _devices = {};
  final Map<String, SensorReading> _latest = {};
  final Map<String, List<StreamSubscription<dynamic>>> _subscriptions = {};
  final Map<String, BleDecoder> _decoders = {};

  final Map<String, SensorInfo> _availableSensors = {};
  final Set<String> _connectedSensorIds = <String>{};
  final StreamController<SensorReading> _sensorDataController =
      StreamController<SensorReading>.broadcast();

  BleSensorManager({this.simulate = false}) {
    if (simulate) {
      _seedSimulatedSensors();
    }
  }

  Stream<SensorReading> get sensorDataStream => _sensorDataController.stream;

  List<SensorInfo> get connectedSensors => _availableSensors.values
      .where((sensor) => _connectedSensorIds.contains(sensor.id))
      .toList();

  Future<List<SensorInfo>> scanForSensors() async {
    if (simulate) {
      _seedSimulatedSensors();
      return List.unmodifiable(_availableSensors.values);
    }

    if (!await FlutterBluePlus.isSupported) {
      throw StateError('Bluetooth LE niet beschikbaar');
    }
    await FlutterBluePlus.startScan(
      withServices: [Guid('180d'), Guid('1816'), Guid('1818')],
      timeout: const Duration(seconds: 6),
    );
    await Future<void>.delayed(const Duration(seconds: 6));
    for (final r in FlutterBluePlus.lastScanResults) {
      final id = r.device.remoteId.str;
      final services = r.advertisementData.serviceUuids
          .map((u) => u.toString().toLowerCase())
          .join(' ');
      final type = services.contains('1818')
          ? SensorType.power
          : services.contains('1816')
          ? SensorType.cadence
          : SensorType.heartRate;
      _devices[id] = r.device;
      _availableSensors[id] = SensorInfo(
        id: id,
        name: r.device.platformName.isEmpty ? 'BLE $id' : r.device.platformName,
        type: type,
        rssi: r.rssi,
        isConnected: isConnected(id),
      );
    }
    return List.unmodifiable(_availableSensors.values);
  }

  Future<void> connectSensor(String sensorId) async {
    final sensor = _availableSensors[sensorId];
    if (sensor == null) {
      throw BluetoothException(
        message: 'Sensor with id $sensorId was not found during scan.',
      );
    }

    if (!simulate) {
      final device = _devices[sensorId]!;
      await device.connect(timeout: const Duration(seconds: 15));
      final subscriptions = <StreamSubscription<dynamic>>[];
      _subscriptions[sensorId] = subscriptions;
      subscriptions.add(
        device.connectionState.listen((state) {
          if (state == BluetoothConnectionState.disconnected) {
            _connectedSensorIds.remove(sensorId);
            _latest.remove(sensorId);
          }
        }),
      );
      try {
        final services = await device.discoverServices();
        for (final service in services) {
          for (final c in service.characteristics) {
            final uuid = c.uuid.toString().toLowerCase();
            if (uuid.contains('2a37') ||
                uuid.contains('2a5b') ||
                uuid.contains('2a63')) {
              await c.setNotifyValue(true);
              subscriptions.add(
                c.onValueReceived.listen((bytes) {
                  try {
                    double? value;
                    var type = sensor.type;
                    if (uuid.contains('2a37')) {
                      value = BleDecoder.heartRate(bytes).toDouble();
                      type = SensorType.heartRate;
                    }
                    if (uuid.contains('2a63')) {
                      value = BleDecoder.power(bytes).toDouble();
                      type = SensorType.power;
                    }
                    if (uuid.contains('2a5b')) {
                      value = (_decoders[sensorId] ??= BleDecoder()).cadence(
                        bytes,
                      );
                      type = SensorType.cadence;
                    }
                    if (value != null) {
                      final reading = SensorReading(
                        sensorId: sensorId,
                        type: type,
                        value: value,
                        timestamp: DateTime.now(),
                      );
                      _latest[sensorId] = reading;
                      _sensorDataController.add(reading);
                    }
                  } on FormatException {
                    /* A malformed radio packet must not end recording. */
                  }
                }),
              );
            }
          }
        }
      } catch (_) {
        await device.disconnect();
        rethrow;
      }
      _connectedSensorIds.add(sensorId);
      return;
    }
    _connectedSensorIds.add(sensorId);
    _availableSensors[sensorId] = sensor.copyWith(isConnected: true);
    _sensorDataController.add(
      SensorReading(
        sensorId: sensorId,
        type: sensor.type,
        value: _generateSampleValue(sensor.type),
        timestamp: DateTime.now(),
        batteryLevel: sensor.batteryLevel,
      ),
    );
  }

  Future<void> disconnectSensor(String sensorId) async {
    final sensor = _availableSensors[sensorId];
    if (sensor == null) {
      return;
    }

    if (!simulate) {
      for (final sub
          in _subscriptions.remove(sensorId) ??
              <StreamSubscription<dynamic>>[]) {
        await sub.cancel();
      }
      await _devices[sensorId]?.disconnect();
      _latest.remove(sensorId);
    }
    _connectedSensorIds.remove(sensorId);
    _availableSensors[sensorId] = sensor.copyWith(isConnected: false);
  }

  bool isConnected(String sensorId) => _connectedSensorIds.contains(sensorId);

  Future<SensorReading?> readLatestReading(String sensorId) async {
    if (!simulate) {
      final r = _latest[sensorId];
      return isConnected(sensorId) &&
              r != null &&
              DateTime.now().difference(r.timestamp).inSeconds <= 10
          ? r
          : null;
    }
    final sensor = _availableSensors[sensorId];
    if (sensor == null) {
      return null;
    }

    return SensorReading(
      sensorId: sensorId,
      type: sensor.type,
      value: _generateSampleValue(sensor.type),
      timestamp: DateTime.now(),
      batteryLevel: sensor.batteryLevel,
    );
  }

  void dispose() {
    for (final list in _subscriptions.values) {
      for (final sub in list) {
        sub.cancel();
      }
    }
    for (final d in _devices.values) {
      d.disconnect();
    }
    _sensorDataController.close();
  }

  void _seedSimulatedSensors() {
    final sensors = <SensorInfo>[
      const SensorInfo(
        id: 'hr-001',
        name: 'Polar H10',
        type: SensorType.heartRate,
        batteryLevel: 87,
        rssi: -48,
      ),
      const SensorInfo(
        id: 'cad-001',
        name: 'Garmin Cadence',
        type: SensorType.cadence,
        batteryLevel: 74,
        rssi: -52,
      ),
      const SensorInfo(
        id: 'pow-001',
        name: 'Favero Power Meter',
        type: SensorType.power,
        batteryLevel: 91,
        rssi: -44,
      ),
    ];

    _availableSensors
      ..clear()
      ..addEntries(sensors.map((sensor) => MapEntry(sensor.id, sensor)));
  }

  double _generateSampleValue(SensorType sensorType) {
    switch (sensorType) {
      case SensorType.heartRate:
        return 156.0;
      case SensorType.cadence:
        return 92.0;
      case SensorType.power:
        return 248.0;
      case SensorType.speed:
        return 31.2;
    }
  }
}
