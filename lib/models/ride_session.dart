import 'package:equatable/equatable.dart';
import 'package:bike_computer/models/gps_models.dart';
import 'package:bike_computer/models/ride_models.dart';

/// State machine states for a ride session
enum RideState {
  idle, // No ride in progress
  ready, // Ready to record, GPS acquired
  recording, // Currently recording
  paused, // Paused during ride
  stopping,
  saving,
  error,
  finished, // Ride ended, ready to save
  saved, // Ride saved to database
}

/// Represents the current state of a ride recording session
class RideSession extends Equatable {
  final String? id; // Database ID, null until saved
  final RideState state;
  final DateTime? startTime;
  final DateTime? endTime;

  // Time tracking
  final Duration elapsedTime;
  final Duration movingTime;
  final Duration pausedTime;

  // Distance and speed
  final double totalDistance; // km
  final double currentSpeed; // km/h
  final double averageSpeed; // km/h
  final double maxSpeed; // km/h

  // Elevation
  final double totalElevationGain; // m
  final double totalElevationLoss; // m
  final double currentElevation; // m
  final double currentGrade; // percent
  final double averageGrade; // percent

  // Track data
  final List<TrackPoint> trackPoints;
  final List<Lap> laps;

  // Sensor data (optional)
  final double? currentHeartRate;
  final double? averageHeartRate;
  final double? maxHeartRate;
  final double? currentCadence;
  final double? averageCadence;
  final double? maxCadence;
  final double? currentPower;
  final double? averagePower;
  final double? maxPower;

  // GPS quality
  final double? currentGpsAccuracy;
  final double? averageGpsAccuracy;

  const RideSession({
    this.id,
    required this.state,
    this.startTime,
    this.endTime,
    this.elapsedTime = const Duration(),
    this.movingTime = const Duration(),
    this.pausedTime = const Duration(),
    this.totalDistance = 0.0,
    this.currentSpeed = 0.0,
    this.averageSpeed = 0.0,
    this.maxSpeed = 0.0,
    this.totalElevationGain = 0.0,
    this.totalElevationLoss = 0.0,
    this.currentElevation = 0.0,
    this.currentGrade = 0.0,
    this.averageGrade = 0.0,
    this.trackPoints = const [],
    this.laps = const [],
    this.currentHeartRate,
    this.averageHeartRate,
    this.maxHeartRate,
    this.currentCadence,
    this.averageCadence,
    this.maxCadence,
    this.currentPower,
    this.averagePower,
    this.maxPower,
    this.currentGpsAccuracy,
    this.averageGpsAccuracy,
  });

  /// Check if currently recording
  bool get isRecording => state == RideState.recording;

  /// Check if ride has data
  bool get hasData => trackPoints.isNotEmpty && totalDistance > 0;

  /// Create a copy with modified fields
  RideSession copyWith({
    bool clearSensors = false,
    bool clearHeartRate = false,
    bool clearCadence = false,
    bool clearPower = false,
    String? id,
    RideState? state,
    DateTime? startTime,
    DateTime? endTime,
    Duration? elapsedTime,
    Duration? movingTime,
    Duration? pausedTime,
    double? totalDistance,
    double? currentSpeed,
    double? averageSpeed,
    double? maxSpeed,
    double? totalElevationGain,
    double? totalElevationLoss,
    double? currentElevation,
    double? currentGrade,
    double? averageGrade,
    List<TrackPoint>? trackPoints,
    List<Lap>? laps,
    double? currentHeartRate,
    double? averageHeartRate,
    double? maxHeartRate,
    double? currentCadence,
    double? averageCadence,
    double? maxCadence,
    double? currentPower,
    double? averagePower,
    double? maxPower,
    double? currentGpsAccuracy,
    double? averageGpsAccuracy,
  }) {
    return RideSession(
      id: id ?? this.id,
      state: state ?? this.state,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      elapsedTime: elapsedTime ?? this.elapsedTime,
      movingTime: movingTime ?? this.movingTime,
      pausedTime: pausedTime ?? this.pausedTime,
      totalDistance: totalDistance ?? this.totalDistance,
      currentSpeed: currentSpeed ?? this.currentSpeed,
      averageSpeed: averageSpeed ?? this.averageSpeed,
      maxSpeed: maxSpeed ?? this.maxSpeed,
      totalElevationGain: totalElevationGain ?? this.totalElevationGain,
      totalElevationLoss: totalElevationLoss ?? this.totalElevationLoss,
      currentElevation: currentElevation ?? this.currentElevation,
      currentGrade: currentGrade ?? this.currentGrade,
      averageGrade: averageGrade ?? this.averageGrade,
      trackPoints: trackPoints ?? this.trackPoints,
      laps: laps ?? this.laps,
      currentHeartRate: (clearSensors || clearHeartRate)
          ? null
          : currentHeartRate ?? this.currentHeartRate,
      averageHeartRate: averageHeartRate ?? this.averageHeartRate,
      maxHeartRate: maxHeartRate ?? this.maxHeartRate,
      currentCadence: (clearSensors || clearCadence)
          ? null
          : currentCadence ?? this.currentCadence,
      averageCadence: averageCadence ?? this.averageCadence,
      maxCadence: maxCadence ?? this.maxCadence,
      currentPower: (clearSensors || clearPower)
          ? null
          : currentPower ?? this.currentPower,
      averagePower: averagePower ?? this.averagePower,
      maxPower: maxPower ?? this.maxPower,
      currentGpsAccuracy: currentGpsAccuracy ?? this.currentGpsAccuracy,
      averageGpsAccuracy: averageGpsAccuracy ?? this.averageGpsAccuracy,
    );
  }

  /// Get aggregate stats
  RideStats getStats() {
    return RideStats(
      totalDistance: totalDistance,
      elapsedTime: elapsedTime,
      movingTime: movingTime,
      pausedTime: pausedTime,
      averageSpeed: averageSpeed,
      maxSpeed: maxSpeed,
      totalElevationGain: totalElevationGain,
      totalElevationLoss: totalElevationLoss,
      averageGrade: averageGrade,
      averageHeartRate: averageHeartRate,
      maxHeartRate: maxHeartRate,
      averageCadence: averageCadence,
      maxCadence: maxCadence,
      averagePower: averagePower,
      maxPower: maxPower,
      numberOfLaps: laps.length,
    );
  }

  @override
  List<Object?> get props => [
    id,
    state,
    startTime,
    endTime,
    elapsedTime,
    movingTime,
    pausedTime,
    totalDistance,
    currentSpeed,
    averageSpeed,
    maxSpeed,
    totalElevationGain,
    totalElevationLoss,
    currentElevation,
    currentGrade,
    averageGrade,
    trackPoints,
    laps,
    currentHeartRate,
    averageHeartRate,
    maxHeartRate,
    currentCadence,
    averageCadence,
    maxCadence,
    currentPower,
    averagePower,
    maxPower,
    currentGpsAccuracy,
    averageGpsAccuracy,
  ];
}
