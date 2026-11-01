import 'package:equatable/equatable.dart';

/// Represents a single GPS track point during a ride
class TrackPoint extends Equatable {
  final double latitude;
  final double longitude;
  final double altitude;
  final DateTime timestamp;
  final double? speed; // m/s
  final double? accuracy; // meters
  final bool segmentStart;
  final double? heading; // degrees 0-360

  const TrackPoint({
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.timestamp,
    this.speed,
    this.accuracy,
    this.heading,
    this.segmentStart = false,
  });

  @override
  List<Object?> get props => [
    latitude,
    longitude,
    altitude,
    timestamp,
    speed,
    accuracy,
    heading,
    segmentStart,
  ];
}

/// Represents GPS location data
class GPSLocation extends Equatable {
  final double latitude;
  final double longitude;
  final double altitude;
  final double accuracy; // meters, lower is better
  final double speed; // m/s
  final double heading; // degrees 0-360
  final DateTime timestamp;

  const GPSLocation({
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.accuracy,
    required this.speed,
    required this.heading,
    required this.timestamp,
  });

  /// Convert to TrackPoint
  TrackPoint toTrackPoint({bool segmentStart = false}) {
    return TrackPoint(
      latitude: latitude,
      longitude: longitude,
      altitude: altitude,
      timestamp: timestamp,
      speed: speed,
      accuracy: accuracy,
      heading: heading,
      segmentStart: segmentStart,
    );
  }

  @override
  List<Object?> get props => [
    latitude,
    longitude,
    altitude,
    accuracy,
    speed,
    heading,
    timestamp,
  ];
}

/// Represents elevation/barometer data
class ElevationData extends Equatable {
  final double elevation; // meters
  final double totalElevationGain; // meters
  final double totalElevationLoss; // meters
  final double currentGrade; // percent
  final double averageGrade; // percent
  final double verticalSpeed; // m/s

  const ElevationData({
    required this.elevation,
    required this.totalElevationGain,
    required this.totalElevationLoss,
    required this.currentGrade,
    required this.averageGrade,
    required this.verticalSpeed,
  });

  @override
  List<Object?> get props => [
    elevation,
    totalElevationGain,
    totalElevationLoss,
    currentGrade,
    averageGrade,
    verticalSpeed,
  ];
}
