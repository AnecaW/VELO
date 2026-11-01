import 'package:equatable/equatable.dart';

/// Supported bike sensors exposed over BLE.
enum SensorType { heartRate, cadence, power, speed }

class SensorInfo extends Equatable {
  final String id;
  final String name;
  final SensorType type;
  final int batteryLevel;
  final int rssi;
  final bool isConnected;

  const SensorInfo({
    required this.id,
    required this.name,
    required this.type,
    this.batteryLevel = 100,
    this.rssi = -60,
    this.isConnected = false,
  });

  SensorInfo copyWith({
    String? id,
    String? name,
    SensorType? type,
    int? batteryLevel,
    int? rssi,
    bool? isConnected,
  }) {
    return SensorInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      rssi: rssi ?? this.rssi,
      isConnected: isConnected ?? this.isConnected,
    );
  }

  @override
  List<Object?> get props => [id, name, type, batteryLevel, rssi, isConnected];
}

class SensorReading extends Equatable {
  final String sensorId;
  final SensorType type;
  final double value;
  final DateTime timestamp;
  final int? batteryLevel;

  const SensorReading({
    required this.sensorId,
    required this.type,
    required this.value,
    required this.timestamp,
    this.batteryLevel,
  });

  @override
  List<Object?> get props => [sensorId, type, value, timestamp, batteryLevel];
}
