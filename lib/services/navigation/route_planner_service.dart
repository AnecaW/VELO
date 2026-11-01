import 'dart:math' as math;

class RoutePoint {
  final double latitude;
  final double longitude;

  const RoutePoint({required this.latitude, required this.longitude});
}

class PlannedRoute {
  final RoutePoint start;
  final RoutePoint destination;
  final double distanceKm;
  final int estimatedMinutes;
  final String summary;

  const PlannedRoute({
    required this.start,
    required this.destination,
    required this.distanceKm,
    required this.estimatedMinutes,
    required this.summary,
  });
}

/// Geodesic estimate only. Road navigation uses RoutingClient.
class RoutePlannerService {
  static PlannedRoute planRoute({
    required RoutePoint start,
    required RoutePoint destination,
    required double averageSpeedKmh,
  }) {
    _validateCoordinate(start.latitude, 'start latitude');
    _validateCoordinate(destination.latitude, 'destination latitude');
    _validateLongitude(start.longitude, 'start longitude');
    _validateLongitude(destination.longitude, 'destination longitude');

    if (averageSpeedKmh <= 0) {
      throw ArgumentError.value(
        averageSpeedKmh,
        'averageSpeedKmh',
        'Average speed must be greater than zero.',
      );
    }

    final distanceKm = _haversineDistanceKm(start, destination);
    final estimatedMinutes = (distanceKm / averageSpeedKmh * 60).round();

    return PlannedRoute(
      start: start,
      destination: destination,
      distanceKm: distanceKm,
      estimatedMinutes: estimatedMinutes,
      summary:
          'Hemelsbreed: ${distanceKm.toStringAsFixed(1)} km • $estimatedMinutes min',
    );
  }

  static void _validateCoordinate(double value, String label) {
    if (value < -90 || value > 90) {
      throw ArgumentError.value(
        value,
        label,
        'Latitude must be between -90 and 90.',
      );
    }
  }

  static void _validateLongitude(double value, String label) {
    if (value < -180 || value > 180) {
      throw ArgumentError.value(
        value,
        label,
        'Longitude must be between -180 and 180.',
      );
    }
  }

  static double _haversineDistanceKm(RoutePoint start, RoutePoint destination) {
    const earthRadiusKm = 6371.0;

    final lat1 = _toRadians(start.latitude);
    final lon1 = _toRadians(start.longitude);
    final lat2 = _toRadians(destination.latitude);
    final lon2 = _toRadians(destination.longitude);

    final dLat = lat2 - lat1;
    final dLon = lon2 - lon1;

    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180;
}
