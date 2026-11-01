import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:bike_computer/services/navigation/gpx_route.dart';

import '../accounts/account_service.dart';

class RoutingClient {
  final http.Client client;
  final AccountService? accounts;
  RoutingClient({http.Client? client, this.accounts})
    : client = client ?? http.Client();
  Future<List<({String label, NavPoint point})>> search(
    String query,
    String key,
  ) async {
    if (accounts == null && key.isEmpty) {
      throw StateError('Geocoding vereist je openrouteservice API-sleutel');
    }
    if (query.trim().length < 3) {
      throw ArgumentError('Vul een adres of plaatsnaam in');
    }
    final uri = Uri.https('api.openrouteservice.org', '/geocode/search', {
      'text': query.trim(),
      'size': '5',
    });
    final dynamic data;
    if (accounts != null) {
      data = await accounts!.request(
        'GET',
        '/api/v1/navigation/search?q=${Uri.encodeQueryComponent(query.trim())}',
      );
    } else {
      final response = await client
          .get(uri, headers: {'Authorization': key})
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw StateError('Adres zoeken mislukt (HTTP ${response.statusCode})');
      }
      data = jsonDecode(response.body);
    }
    final features = data['features'] as List;
    return features.map((f) {
      final c = f['geometry']['coordinates'];
      return (
        label: f['properties']['label'].toString(),
        point: NavPoint((c[1] as num).toDouble(), (c[0] as num).toDouble()),
      );
    }).toList();
  }

  Future<NavRoute> route(
    NavPoint start,
    NavPoint end,
    String key, {
    String profile = 'cycling-regular',
  }) async {
    if (accounts == null && key.trim().isEmpty) {
      throw StateError(
        'Stel eerst je openrouteservice API-sleutel in bij Integrations.',
      );
    }
    if (![
      'cycling-regular',
      'cycling-road',
      'cycling-mountain',
      'cycling-electric',
    ].contains(profile)) {
      throw ArgumentError('Profiel niet ondersteund');
    }
    final dynamic data;
    if (accounts != null) {
      data = await accounts!.request(
        'POST',
        '/api/v1/navigation/directions',
        body: {
          'coordinates': [
            [start.lon, start.lat],
            [end.lon, end.lat],
          ],
          'profile': profile,
        },
      );
    } else {
      final response = await client
          .post(
            Uri.parse(
              'https://api.openrouteservice.org/v2/directions/$profile/geojson',
            ),
            headers: {'Authorization': key, 'Content-Type': 'application/json'},
            body: jsonEncode({
              'coordinates': [
                [start.lon, start.lat],
                [end.lon, end.lat],
              ],
              'elevation': true,
              'instructions': true,
            }),
          )
          .timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) {
        throw StateError(
          'Routering mislukt (HTTP ${response.statusCode}); bestaande route blijft beschikbaar.',
        );
      }
      data = jsonDecode(response.body);
    }
    final feature = data['features'][0];
    final coords = feature['geometry']['coordinates'] as List;
    if (coords.length < 2) {
      throw const FormatException('Provider leverde geen route');
    }
    final points = coords
        .map(
          (p) => NavPoint(
            (p[1] as num).toDouble(),
            (p[0] as num).toDouble(),
            p.length > 2 ? (p[2] as num).toDouble() : null,
          ),
        )
        .toList();
    final steps = <NavStep>[];
    for (final segment in feature['properties']['segments'] as List) {
      for (final s in segment['steps'] as List) {
        steps.add(
          NavStep((s['way_points'][0] as num).toInt(), s['instruction']),
        );
      }
    }
    return NavRoute('Fietsroute', points, steps: steps);
  }

  void dispose() => client.close();
}
