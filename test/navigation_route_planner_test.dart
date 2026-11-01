import 'package:flutter_test/flutter_test.dart';
import 'package:bike_computer/services/navigation/route_planner_service.dart';

void main() {
  group('RoutePlannerService', () {
    test('calculates route distance and ETA from two coordinates', () {
      const start = RoutePoint(latitude: 51.2194, longitude: 4.4025);
      const destination = RoutePoint(latitude: 50.8503, longitude: 4.3517);

      final route = RoutePlannerService.planRoute(
        start: start,
        destination: destination,
        averageSpeedKmh: 28,
      );

      expect(route.distanceKm, greaterThan(0));
      expect(route.estimatedMinutes, greaterThan(0));
      expect(route.summary, contains('km'));
      expect(route.summary, contains('min'));
    });

    test('rejects invalid coordinates', () {
      const start = RoutePoint(latitude: 91, longitude: 4.4025);
      const destination = RoutePoint(latitude: 50.8503, longitude: 4.3517);

      expect(
        () => RoutePlannerService.planRoute(
          start: start,
          destination: destination,
          averageSpeedKmh: 28,
        ),
        throwsArgumentError,
      );
    });
  });
}
