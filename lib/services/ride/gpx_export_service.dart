import 'package:bike_computer/models/ride_session.dart';

class GpxExportService {
  static String _escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
  static String exportToGpx(RideSession session) {
    final out = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8"?>\n<gpx xmlns="http://www.topografix.com/GPX/1/1" version="1.1" creator="Ultimate Bike Computer"><metadata><name>Bike Computer Ride</name></metadata><trk><name>Ride ${_escape(session.id ?? 'session')}</name><trkseg>',
    );
    for (var i = 0; i < session.trackPoints.length; i++) {
      final p = session.trackPoints[i];
      if (!p.latitude.isFinite ||
          !p.longitude.isFinite ||
          p.latitude.abs() > 90 ||
          p.longitude.abs() > 180) {
        throw const FormatException('Invalid GPX coordinate');
      }
      if (i > 0 && p.segmentStart) out.write('</trkseg><trkseg>');
      out.write(
        '<trkpt lat="${p.latitude.toStringAsFixed(6)}" lon="${p.longitude.toStringAsFixed(6)}">',
      );
      if (p.altitude.isFinite) {
        out.write('<ele>${p.altitude.toStringAsFixed(1)}</ele>');
      }
      out.write(
        '<time>${p.timestamp.toUtc().toIso8601String()}</time></trkpt>',
      );
    }
    out.write('</trkseg></trk></gpx>');
    return out.toString();
  }
}
