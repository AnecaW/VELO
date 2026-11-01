import 'dart:convert';

import 'package:xml/xml.dart';
import 'package:latlong2/latlong.dart' hide DistanceCalculator;
import 'package:bike_computer/services/ride/calculations.dart';

class NavPoint {
  final double lat, lon;
  final double? elevation;
  final bool breakBefore;
  const NavPoint(
    this.lat,
    this.lon, [
    this.elevation,
    this.breakBefore = false,
  ]);
  LatLng get coordinate => LatLng(lat, lon);
  List<dynamic> toJson() => [lat, lon, elevation, breakBefore];
}

class NavStep {
  final int index;
  final String instruction;
  const NavStep(this.index, this.instruction);
}

class NavRoute {
  final String name;
  final List<NavPoint> points, waypoints;
  final List<NavStep> steps;
  const NavRoute(
    this.name,
    this.points, {
    this.waypoints = const [],
    this.steps = const [],
  });
  double get meters {
    var value = 0.0;
    for (var i = 1; i < points.length; i++) {
      if (!points[i].breakBefore) value += distance(points[i - 1], points[i]);
    }
    return value;
  }

  double metersTo(int index) {
    var value = 0.0;
    for (var i = 1; i <= index && i < points.length; i++) {
      if (!points[i].breakBefore) value += distance(points[i - 1], points[i]);
    }
    return value;
  }

  String encode() => jsonEncode({
    'name': name,
    'points': points.map((p) => p.toJson()).toList(),
    'waypoints': waypoints.map((p) => p.toJson()).toList(),
    'steps': steps.map((s) => [s.index, s.instruction]).toList(),
  });
  static NavRoute decode(String raw) {
    final j = jsonDecode(raw);
    NavPoint point(dynamic p) => NavPoint(
      (p[0] as num).toDouble(),
      (p[1] as num).toDouble(),
      (p[2] as num?)?.toDouble(),
      p.length > 3 ? p[3] as bool : false,
    );
    return NavRoute(
      j['name'],
      (j['points'] as List).map(point).toList(),
      waypoints: (j['waypoints'] as List).map(point).toList(),
      steps: (j['steps'] as List).map((s) => NavStep(s[0], s[1])).toList(),
    );
  }

  static double distance(NavPoint a, NavPoint b) =>
      DistanceCalculator.distanceInMeters(a.lat, a.lon, b.lat, b.lon);
}

/// Rejects entity declarations and bounded input before parsing untrusted XML.
NavRoute parseGpx(String source) {
  if (utf8.encode(source).length > 10 * 1024 * 1024) {
    throw const FormatException('GPX groter dan 10 MB');
  }
  if (RegExp(r'<!DOCTYPE|<!ENTITY', caseSensitive: false).hasMatch(source)) {
    throw const FormatException('XML entities niet toegestaan');
  }
  final document = XmlDocument.parse(source);
  if (document.rootElement.name.local != 'gpx') {
    throw const FormatException('Geen GPX-bestand');
  }
  final points = <NavPoint>[], waypoints = <NavPoint>[];
  String name = 'GPX route';
  for (final node in document.descendants.whereType<XmlElement>()) {
    final tag = node.name.local;
    if (tag == 'name' && name == 'GPX route') name = node.innerText;
    if (tag != 'trkpt' && tag != 'rtept' && tag != 'wpt') continue;
    final lat = double.tryParse(node.getAttribute('lat') ?? '');
    final lon = double.tryParse(node.getAttribute('lon') ?? '');
    if (lat == null ||
        lon == null ||
        !lat.isFinite ||
        !lon.isFinite ||
        lat.abs() > 90 ||
        lon.abs() > 180) {
      throw const FormatException('Ongeldige GPX-coördinaat');
    }
    final ele = node.childElements
        .where((e) => e.name.local == 'ele')
        .firstOrNull;
    final elevation = ele == null ? null : double.tryParse(ele.innerText);
    if (elevation != null && !elevation.isFinite) {
      throw const FormatException('Ongeldige hoogte');
    }
    final parent = node.parent;
    final starts =
        tag != 'wpt' &&
        points.isNotEmpty &&
        parent is XmlElement &&
        parent.childElements.where((e) => e.name.local == tag).firstOrNull ==
            node;
    final p = NavPoint(lat, lon, elevation, starts);
    if (tag == 'wpt') {
      waypoints.add(p);
    } else {
      points.add(p);
    }
    if (points.length + waypoints.length > 100000) {
      throw const FormatException('Te veel GPX-punten');
    }
  }
  if (points.length < 2) {
    throw const FormatException(
      'GPX bevat geen route of track met minstens twee punten',
    );
  }
  return NavRoute(name, points, waypoints: waypoints);
}

class RouteProgress {
  final double traveled, remaining, offRouteMeters;
  final int segment;
  final bool offRoute;
  const RouteProgress(
    this.traveled,
    this.remaining,
    this.offRouteMeters,
    this.segment,
    this.offRoute,
  );
  static RouteProgress locate(
    NavRoute route,
    NavPoint location, {
    double accuracy = 10,
    double threshold = 40,
  }) {
    var best = double.infinity, traveled = 0.0, bestTraveled = 0.0;
    var segment = 0;
    final cosLat =
        const Distance().as(
          LengthUnit.Meter,
          LatLng(location.lat, 0),
          LatLng(location.lat, 0.01),
        ) /
        0.01;
    const latScale = 111195.0;
    for (var i = 1; i < route.points.length; i++) {
      final a = route.points[i - 1], b = route.points[i];
      if (b.breakBefore) continue;
      final ax = (a.lon - location.lon) * cosLat,
          ay = (a.lat - location.lat) * latScale;
      final bx = (b.lon - location.lon) * cosLat,
          by = (b.lat - location.lat) * latScale;
      final dx = bx - ax, dy = by - ay, length2 = dx * dx + dy * dy;
      final t = length2 == 0
          ? 0.0
          : (-(ax * dx + ay * dy) / length2).clamp(0.0, 1.0);
      final projected = NavPoint(
        location.lat + (ay + t * dy) / latScale,
        location.lon + (cosLat.abs() < 1 ? 0 : (ax + t * dx) / cosLat),
      );
      final distance = NavRoute.distance(location, projected);
      final length = NavRoute.distance(a, b);
      if (distance < best) {
        best = distance;
        bestTraveled = traveled + length * t;
        segment = i;
      }
      traveled += length;
    }
    return RouteProgress(
      bestTraveled,
      (traveled - bestTraveled).clamp(0, double.infinity),
      best,
      segment,
      best > threshold + accuracy,
    );
  }
}
