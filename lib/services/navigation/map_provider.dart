import 'dart:math' as math;

import 'package:maplibre_gl/maplibre_gl.dart' as ml;

class MapStyleSpec {
  final String id, name, url, provider;
  final bool offline;
  const MapStyleSpec(
    this.id,
    this.name,
    this.url,
    this.provider, {
    this.offline = false,
  });
  static const builtins = [
    MapStyleSpec(
      'dark',
      'Midnight',
      'https://tiles.openfreemap.org/styles/dark',
      'OpenFreeMap',
      offline: true,
    ),
    MapStyleSpec(
      'light',
      'Daylight',
      'https://tiles.openfreemap.org/styles/positron',
      'OpenFreeMap',
      offline: true,
    ),
    MapStyleSpec(
      'streets',
      'Cycle streets',
      'https://tiles.openfreemap.org/styles/liberty',
      'OpenFreeMap',
      offline: true,
    ),
  ];
}

Future<void>? _configured;
Future<void> configureMapNetworking() => _configured ??= Future<void>(() async {
  await ml.setHttpHeaders({
    'User-Agent': 'UltimateBikeComputer/2.0 (com.example.bike_computer; personal cycling)',
  });
  await ml.setOfflineMaxConcurrentRequests(
    maxRequests: 4,
    maxRequestsPerHost: 4,
  );
  await ml.setOfflineTileCountLimit(3000);
});

class DownloadBounds {
  final double south, west, north, east;
  final int minZoom, maxZoom;
  const DownloadBounds(
    this.south,
    this.west,
    this.north,
    this.east,
    this.minZoom,
    this.maxZoom,
  );
  int get tiles {
    int sum = 0;
    for (var z = minZoom; z <= maxZoom; z++) {
      final n = math.pow(2, z);
      int x(double lon) => ((lon + 180) / 360 * n).floor();
      int y(double lat) =>
          ((1 -
                      math.log(math.tan(math.pi / 4 + lat * math.pi / 360)) /
                          math.pi) /
                  2 *
                  n)
              .floor();
      sum += (x(east) - x(west) + 1) * (y(south) - y(north) + 1);
    }
    return sum;
  }

  void validate() {
    if (![south, west, north, east].every((n) => n.isFinite) ||
        south < -85 ||
        north > 85 ||
        south >= north ||
        west < -180 ||
        east > 180 ||
        west >= east ||
        minZoom < 0 ||
        maxZoom > 16 ||
        minZoom > maxZoom ||
        tiles > 2500) {
      throw const FormatException(
        'Kies een kleiner gebied of minder zoomniveaus (maximaal 2.500 geraamde tegels).',
      );
    }
  }

  ml.LatLngBounds get bounds => ml.LatLngBounds(
    southwest: ml.LatLng(south, west),
    northeast: ml.LatLng(north, east),
  );
}
