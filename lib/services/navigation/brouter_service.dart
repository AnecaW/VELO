import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/bike_type.dart';
import 'gpx_route.dart';

abstract class CyclingRouter {
  Future<NavRoute> calculate(
    NavPoint start,
    NavPoint end,
    BikeType bike, {
    int alternative = 0,
  });
  void dispose();
}

class BRouterService implements CyclingRouter {
  final http.Client client;
  final Uri endpoint;
  BRouterService({http.Client? client, Uri? endpoint})
    : client = client ?? http.Client(),
      endpoint =
          endpoint ??
          Uri.parse(
            const String.fromEnvironment(
              'BROUTER_URL',
              defaultValue: 'https://brouter.de/brouter',
            ),
          );
  @override
  Future<NavRoute> calculate(
    NavPoint start,
    NavPoint end,
    BikeType bike, {
    int alternative = 0,
  }) async {
    for (final p in [start, end]) {
      if (!p.lat.isFinite ||
          !p.lon.isFinite ||
          p.lat.abs() > 90 ||
          p.lon.abs() > 180) {
        throw const FormatException('Ongeldige routepositie');
      }
    }
    if (NavRoute.distance(start, end) > 200000) {
      throw StateError(
        'Kies voor de publieke router een bestemming binnen 200 km.',
      );
    }
    final uri = endpoint.replace(
      queryParameters: {
        'lonlats': '${start.lon},${start.lat}|${end.lon},${end.lat}',
        'profile': bike.routingProfile,
        'alternativeidx': '${alternative.clamp(0, 2)}',
        'format': 'geojson',
        'timode': '1',
      },
    );
    final response = await client
        .get(uri, headers: {'User-Agent': 'VELO/2.6 (cycling navigation)'})
        .timeout(const Duration(seconds: 45));
    if (response.statusCode != 200) {
      throw StateError(
        response.statusCode == 429
            ? 'Routingdienst is druk. Wacht even en probeer opnieuw.'
            : 'Geen fietsroute ontvangen. De publieke router is mogelijk tijdelijk niet beschikbaar.',
      );
    }
    return parse(jsonDecode(response.body), bike, alternative);
  }

  static NavRoute parse(dynamic data, BikeType bike, int alternative) {
    final features = data['features'] as List;
    if (features.isEmpty) throw const FormatException('Geen route gevonden');
    final f = features.first, props = f['properties'] as Map;
    final points = (f['geometry']['coordinates'] as List)
        .map(
          (c) => NavPoint(
            (c[1] as num).toDouble(),
            (c[0] as num).toDouble(),
            c.length > 2 ? (c[2] as num?)?.toDouble() : null,
          ),
        )
        .toList();
    if (points.length < 2 ||
        points.length > 100000 ||
        points.any(
          (p) =>
              !p.lat.isFinite ||
              !p.lon.isFinite ||
              p.lat.abs() > 90 ||
              p.lon.abs() > 180 ||
              (p.elevation != null && !p.elevation!.isFinite),
        )) {
      throw const FormatException('Ongeldige routegegevens');
    }
    const turns = {
      1: 'Ga rechtdoor',
      2: 'Sla linksaf',
      3: 'Houd schuin links aan',
      4: 'Sla scherp linksaf',
      5: 'Sla rechtsaf',
      6: 'Houd schuin rechts aan',
      7: 'Sla scherp rechtsaf',
      8: 'Houd links aan',
      9: 'Houd rechts aan',
      10: 'Keer om',
      11: 'Keer rechtsom',
      15: 'Keer om',
      17: 'Neem de afslag links',
      18: 'Neem de afslag rechts',
      100: 'Je bent aangekomen',
    };
    final steps = <NavStep>[];
    for (final h in props['voicehints'] as List? ?? []) {
      final index = (h[0] as num).toInt(), cmd = (h[1] as num).toInt();
      final instruction = cmd == 13 || cmd == 14
          ? 'Neem op de rotonde afslag ${(h[2] as num).abs().toInt()}'
          : turns[cmd];
      if (index >= 0 && index < points.length && instruction != null) {
        steps.add(NavStep(index, instruction));
      }
    }
    steps.sort((a, b) => a.index.compareTo(b.index));
    double? number(String k) {
      final n = double.tryParse('${props[k]}');
      return n != null && n.isFinite && n >= 0 ? n : null;
    }

    return NavRoute(
      alternative == 0
          ? 'Fietsroute · ${bike.label}'
          : 'Alternatief $alternative · ${bike.label}',
      points,
      steps: steps,
      provider: 'BRouter',
      bikeType: bike.name,
      durationSeconds: number('total-time'),
      ascent: number('filtered ascend'),
    );
  }

  @override
  void dispose() => client.close();
}
