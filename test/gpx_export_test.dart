import 'package:flutter_test/flutter_test.dart';
import 'package:bike_computer/models/gps_models.dart';
import 'package:bike_computer/models/ride_session.dart';
import 'package:bike_computer/services/ride/gpx_export_service.dart';

void main() {
  group('GpxExportService', () {
    test('creates a valid GPX document from a ride session', () {
      final session = RideSession(
        state: RideState.finished,
        startTime: DateTime(2024, 1, 1, 9, 0, 0),
        endTime: DateTime(2024, 1, 1, 9, 30, 0),
        totalDistance: 18.4,
        totalElevationGain: 120,
        trackPoints: [
          TrackPoint(
            latitude: 51.2194,
            longitude: 4.4025,
            altitude: 10,
            timestamp: DateTime(2024, 1, 1, 9, 0, 0),
          ),
          TrackPoint(
            latitude: 51.2200,
            longitude: 4.4030,
            altitude: 12,
            timestamp: DateTime(2024, 1, 1, 9, 5, 0),
          ),
          TrackPoint(
            latitude: 51.2210,
            longitude: 4.4050,
            altitude: 14,
            timestamp: DateTime(2024, 1, 1, 9, 10, 0),
          ),
        ],
      );

      final gpx = GpxExportService.exportToGpx(session);

      expect(gpx, contains('<gpx'));
      expect(gpx, contains('<trkpt lat="51.219400" lon="4.402500">'));
      expect(gpx, contains('<ele>10.0</ele>'));
      expect(gpx, contains('</gpx>'));
    });

    test('returns empty GPX for a ride without track points', () {
      const session = RideSession(state: RideState.ready);

      final gpx = GpxExportService.exportToGpx(session);

      expect(gpx, contains('<gpx'));
      expect(gpx, contains('<trkseg>'));
    });
  });
}
