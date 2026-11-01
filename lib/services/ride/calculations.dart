import 'dart:math' as math;

import 'package:bike_computer/models/gps_models.dart';

/// Service for calculating distance between two points using Haversine formula
class DistanceCalculator {
  static const double earthRadiusKm = 6371.0;
  static const double earthRadiusM = 6371000.0;

  /// Calculate distance in kilometers between two GPS coordinates
  static double distanceInKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    return _haversine(lat1, lon1, lat2, lon2) * earthRadiusKm;
  }

  /// Calculate distance in meters between two GPS coordinates
  static double distanceInMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    return _haversine(lat1, lon1, lat2, lon2) * earthRadiusM;
  }

  /// Haversine formula for great-circle distance
  static double _haversine(double lat1, double lon1, double lat2, double lon2) {
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degreesToRadians(lat1)) *
            math.cos(_degreesToRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return c;
  }

  static double _degreesToRadians(double degrees) {
    return degrees * math.pi / 180.0;
  }
}

/// Service for smooth elevation/altitude calculations
class ElevationService {
  // Smoothing window size (number of points)
  static const int smoothingWindowSize = 5;

  /// Apply smoothing to elevation data using moving average
  static double smoothElevation(List<double> recentAltitudes) {
    if (recentAltitudes.isEmpty) return 0.0;
    if (recentAltitudes.length == 1) return recentAltitudes.first;

    final window = recentAltitudes.sublist(
      math.max(0, recentAltitudes.length - smoothingWindowSize),
    );
    return window.reduce((a, b) => a + b) / window.length;
  }

  /// Calculate grade (percent) between two elevation points
  static double calculateGrade(double elevationChange, double distanceMeters) {
    if (distanceMeters == 0) return 0.0;
    return (elevationChange / distanceMeters) * 100.0;
  }

  /// Detect if elevation gain/loss
  static void updateElevationStats({
    required double currentElevation,
    required double lastElevation,
    required double elevationThreshold, // meters, default 1.0
    required Function(double gain, double loss) onUpdate,
  }) {
    final diff = currentElevation - lastElevation;

    if (diff > elevationThreshold) {
      onUpdate(diff, 0.0); // Gain
    } else if (diff < -elevationThreshold) {
      onUpdate(0.0, -diff); // Loss
    }
  }

  /// Calculate vertical speed in m/s
  static double calculateVerticalSpeed(
    double elevationDelta, // meters
    Duration timeDelta,
  ) {
    if (timeDelta.inSeconds == 0) return 0.0;
    return elevationDelta / timeDelta.inSeconds;
  }
}

/// Service for speed calculations and smoothing
class SpeedCalculator {
  /// Calculate speed in km/h from meters and seconds
  static double speedKmh(double meters, int seconds) {
    if (seconds == 0) return 0.0;
    return (meters / seconds) * 3.6; // 3.6 = 3600 seconds / 1000 meters
  }

  /// Calculate speed in m/s
  static double speedMs(double meters, int seconds) {
    if (seconds == 0) return 0.0;
    return meters / seconds;
  }

  /// Apply exponential smoothing to speed
  static double smoothSpeed(
    double currentSpeed,
    double lastSmoothedSpeed,
    double alpha, // Smoothing factor 0.0-1.0, lower = more smooth
  ) {
    return alpha * currentSpeed + (1 - alpha) * lastSmoothedSpeed;
  }

  /// Detect if moving (above speed threshold)
  static bool isMoving(double speedKmh, double thresholdKmh) {
    return speedKmh > thresholdKmh;
  }

  /// Calculate average speed
  static double averageSpeed(double distanceKm, Duration movingTime) {
    if (movingTime.inSeconds == 0) return 0.0;
    return distanceKm / (movingTime.inSeconds / 3600.0);
  }
}

/// Comprehensive ride calculations
class RideCalculator {
  /// Calculate total distance from track points
  static double calculateDistance(List<TrackPoint> trackPoints) {
    if (trackPoints.length < 2) return 0.0;

    double totalDistance = 0.0;
    for (int i = 1; i < trackPoints.length; i++) {
      final prev = trackPoints[i - 1];
      final curr = trackPoints[i];

      final distance = DistanceCalculator.distanceInMeters(
        prev.latitude,
        prev.longitude,
        curr.latitude,
        curr.longitude,
      );

      totalDistance += distance;
    }

    return totalDistance / 1000.0; // Convert to km
  }

  /// Calculate elevation statistics
  static ({double gain, double loss}) calculateElevationStats(
    List<TrackPoint> trackPoints,
  ) {
    if (trackPoints.length < 2) return (gain: 0.0, loss: 0.0);

    double totalGain = 0.0;
    double totalLoss = 0.0;
    const elevationThreshold = 1.0; // meters

    for (int i = 1; i < trackPoints.length; i++) {
      final diff = trackPoints[i].altitude - trackPoints[i - 1].altitude;

      if (diff > elevationThreshold) {
        totalGain += diff;
      } else if (diff < -elevationThreshold) {
        totalLoss += -diff;
      }
    }

    return (gain: totalGain, loss: totalLoss);
  }

  /// Calculate average grade from track
  static double calculateAverageGrade(double elevationGain, double distanceKm) {
    if (distanceKm == 0) return 0.0;
    return (elevationGain / (distanceKm * 1000)) * 100.0;
  }

  /// Calculate pace (minutes per km)
  static double calculatePace(Duration movingTime, double distanceKm) {
    if (distanceKm == 0) return 0.0;
    return movingTime.inSeconds / 60.0 / distanceKm;
  }
}
