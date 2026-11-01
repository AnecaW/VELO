import 'package:equatable/equatable.dart';

/// Represents a single lap during a ride
class Lap extends Equatable {
  final int lapNumber;
  final DateTime startTime;
  final Duration duration;
  final double distance; // km
  final double averageSpeed; // km/h
  final double maxSpeed; // km/h
  final double? averageHeartRate;
  final double? maxHeartRate;
  final double? averageCadence;
  final double? averagePower;
  final double elevationGain; // m
  final double elevationLoss; // m

  const Lap({
    required this.lapNumber,
    required this.startTime,
    required this.duration,
    required this.distance,
    required this.averageSpeed,
    required this.maxSpeed,
    this.averageHeartRate,
    this.maxHeartRate,
    this.averageCadence,
    this.averagePower,
    required this.elevationGain,
    required this.elevationLoss,
  });

  @override
  List<Object?> get props => [
    lapNumber,
    startTime,
    duration,
    distance,
    averageSpeed,
    maxSpeed,
    averageHeartRate,
    maxHeartRate,
    averageCadence,
    averagePower,
    elevationGain,
    elevationLoss,
  ];
}

/// Aggregated ride statistics
class RideStats extends Equatable {
  final double totalDistance; // km
  final Duration elapsedTime;
  final Duration movingTime;
  final Duration pausedTime;
  final double averageSpeed; // km/h
  final double maxSpeed; // km/h
  final double totalElevationGain; // m
  final double totalElevationLoss; // m
  final double averageGrade; // percent
  final double? averageHeartRate;
  final double? maxHeartRate;
  final double? averageCadence;
  final double? maxCadence;
  final double? averagePower;
  final double? maxPower;
  final int numberOfLaps;

  const RideStats({
    required this.totalDistance,
    required this.elapsedTime,
    required this.movingTime,
    required this.pausedTime,
    required this.averageSpeed,
    required this.maxSpeed,
    required this.totalElevationGain,
    required this.totalElevationLoss,
    required this.averageGrade,
    this.averageHeartRate,
    this.maxHeartRate,
    this.averageCadence,
    this.maxCadence,
    this.averagePower,
    this.maxPower,
    required this.numberOfLaps,
  });

  @override
  List<Object?> get props => [
    totalDistance,
    elapsedTime,
    movingTime,
    pausedTime,
    averageSpeed,
    maxSpeed,
    totalElevationGain,
    totalElevationLoss,
    averageGrade,
    averageHeartRate,
    maxHeartRate,
    averageCadence,
    maxCadence,
    averagePower,
    maxPower,
    numberOfLaps,
  ];
}
