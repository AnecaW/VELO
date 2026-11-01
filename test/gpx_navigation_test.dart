import 'package:flutter_test/flutter_test.dart';
import 'package:bike_computer/services/navigation/gpx_route.dart';
import 'package:bike_computer/services/ride/gpx_export_service.dart';
import 'package:bike_computer/models/gps_models.dart';
import 'package:bike_computer/models/ride_session.dart';

void main() {
  const source =
      '<gpx version="1.1"><metadata><name>Local route</name></metadata><wpt lat="51" lon="4"/><trk><trkseg><trkpt lat="51" lon="4"><ele>10</ele></trkpt><trkpt lat="51.01" lon="4"><ele>40</ele></trkpt></trkseg></trk></gpx>';
  test('GPX imports track, elevation and waypoints', () {
    final r = parseGpx(source);
    expect(r.points.length, 2);
    expect(r.waypoints.length, 1);
    expect(r.points.last.elevation, 40);
    expect(r.name, 'Local route');
    expect(r.meters, greaterThan(1000));
  });
  test('GPX imports rtept routes', () {
    expect(
      parseGpx(
        '<gpx><rte><rtept lat="50" lon="4"/><rtept lat="51" lon="4"/></rte></gpx>',
      ).points.length,
      2,
    );
  });
  test('GPX rejects entity, invalid coordinate and malformed XML', () {
    for (final bad in [
      '<!DOCTYPE gpx><gpx/>',
      '<gpx><trkpt lat="NaN" lon="4"/></gpx>',
      '<gpx>',
    ]) {
      expect(() => parseGpx(bad), throwsA(isA<Exception>()));
    }
  });
  test('GPX roundtrip preserves coordinate precision and segments', () {
    final s = RideSession(
      state: RideState.finished,
      id: '<unsafe&>',
      trackPoints: [
        TrackPoint(
          latitude: 51,
          longitude: 4,
          altitude: 10,
          timestamp: DateTime.utc(2026),
        ),
        TrackPoint(
          latitude: 51.01,
          longitude: 4,
          altitude: 40,
          timestamp: DateTime.utc(2026),
          segmentStart: true,
        ),
      ],
    );
    final xml = GpxExportService.exportToGpx(s);
    expect(xml, contains('&lt;unsafe&amp;&gt;'));
    expect(RegExp('<trkseg>').allMatches(xml).length, 2);
    expect(parseGpx(xml).points.length, 2);
  });
  test('route progress projects onto segment instead of nearest vertex', () {
    final r = parseGpx(source);
    final p = RouteProgress.locate(r, const NavPoint(51.005, 4));
    expect(p.traveled, closeTo(r.meters / 2, 3));
    expect(p.remaining, closeTo(r.meters / 2, 3));
    expect(p.offRoute, isFalse);
  });
  test('off route threshold accounts for accuracy', () {
    final r = parseGpx(source);
    expect(
      RouteProgress.locate(r, const NavPoint(51.005, 4.01)).offRoute,
      isTrue,
    );
    expect(
      RouteProgress.locate(
        r,
        const NavPoint(51.005, 4.0005),
        accuracy: 50,
      ).offRoute,
      isFalse,
    );
  });
  test(
    'disconnected GPX segments never create a fictitious connecting route',
    () {
      final route = parseGpx(
        '<gpx><trk><trkseg><trkpt lat="51" lon="4"/><trkpt lat="51.001" lon="4"/></trkseg><trkseg><trkpt lat="52" lon="5"/><trkpt lat="52.001" lon="5"/></trkseg></trk></gpx>',
      );
      expect(route.points[2].breakBefore, isTrue);
      expect(route.meters, closeTo(222.4, 2));
      expect(NavRoute.decode(route.encode()).points[2].breakBefore, isTrue);
    },
  );
  test('local route serialization retains instructions', () {
    const r = NavRoute(
      'offline',
      [NavPoint(51, 4), NavPoint(51.01, 4)],
      steps: [NavStep(1, 'Turn right')],
    );
    expect(NavRoute.decode(r.encode()).steps.single.instruction, 'Turn right');
  });
}
