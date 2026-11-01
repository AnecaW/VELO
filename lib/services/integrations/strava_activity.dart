import '../navigation/gpx_route.dart';

/// Decode only the polyline supplied by Strava; never invent trackpoints.
List<NavPoint> stravaPolyline(String encoded) {
  if (encoded.length > 1000000) {
    throw const FormatException('Kaartspoor te groot');
  }
  final points = <NavPoint>[];
  var index = 0, lat = 0, lon = 0;
  int value() {
    var result = 0, shift = 0, byte = 0;
    do {
      if (index >= encoded.length || shift > 30) {
        throw const FormatException('Ongeldig Strava-kaartspoor');
      }
      byte = encoded.codeUnitAt(index++) - 63;
      if (byte < 0 || byte > 63) {
        throw const FormatException('Ongeldig Strava-kaartspoor');
      }
      result |= (byte & 31) << shift;
      shift += 5;
    } while (byte >= 32);
    return result & 1 == 1 ? ~(result >> 1) : result >> 1;
  }

  while (index < encoded.length) {
    lat += value();
    lon += value();
    final a = lat / 1e5, b = lon / 1e5;
    if (a.abs() > 90 || b.abs() > 180) {
      throw const FormatException('Ongeldige Strava-coördinaten');
    }
    points.add(NavPoint(a, b));
  }
  return points;
}

String stravaDuration(num? seconds) {
  final value = Duration(seconds: seconds?.toInt() ?? 0);
  return '${value.inHours}:${(value.inMinutes % 60).toString().padLeft(2, '0')}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';
}
