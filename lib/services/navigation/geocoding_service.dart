import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../database/bike_computer_database.dart';
import 'gpx_route.dart';

class AddressResult {
  final String title, subtitle;
  final NavPoint point;
  const AddressResult(this.title, this.subtitle, this.point);
  String get label => subtitle.isEmpty ? title : '$title, $subtitle';
  Map<String, dynamic> toJson() => {
    'title': title,
    'subtitle': subtitle,
    'point': point.toJson(),
  };
  factory AddressResult.fromJson(Map<String, dynamic> j) => AddressResult(
    j['title'],
    j['subtitle'],
    NavPoint(
      (j['point'][0] as num).toDouble(),
      (j['point'][1] as num).toDouble(),
    ),
  );
}

abstract class GeocodingService {
  Future<List<AddressResult>> search(String query, {NavPoint? focus});
  Future<AddressResult?> reverse(NavPoint point);
  void dispose();
}

class PhotonGeocoder implements GeocodingService {
  final http.Client client;
  final BikeComputerDatabase database;
  final Uri endpoint;
  bool cached = false;
  DateTime? _lastRequest;
  Future<void> _queue = Future.value();
  PhotonGeocoder(this.database, {http.Client? client, Uri? endpoint})
    : client = client ?? http.Client(),
      endpoint =
          endpoint ??
          Uri.parse(
            const String.fromEnvironment(
              'PHOTON_URL',
              defaultValue: 'https://photon.komoot.io',
            ),
          );
  Future<dynamic> _fetch(String path, Map<String, String> params) async {
    final previous = _queue;
    final complete = Completer<void>();
    _queue = complete.future;
    await previous;
    try {
      final wait = _lastRequest == null
          ? Duration.zero
          : const Duration(seconds: 1) -
                DateTime.now().difference(_lastRequest!);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
      _lastRequest = DateTime.now();
      final response = await client
          .get(
            endpoint.replace(
              path: '${endpoint.path}$path',
              queryParameters: params,
            ),
            headers: {'User-Agent': 'VELO/2.6 (cycling navigation)'},
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw StateError(
          response.statusCode == 429
              ? 'Adresdienst is druk. Wacht even en probeer opnieuw.'
              : 'Adresdienst tijdelijk onbereikbaar. Probeer opnieuw.',
        );
      }
      return jsonDecode(response.body);
    } finally {
      complete.complete();
    }
  }

  List<AddressResult> _parse(dynamic data) {
    final results = <AddressResult>[];
    final seen = <String>{};
    for (final f in data['features'] as List) {
      final p = f['properties'] as Map;
      final c = f['geometry']['coordinates'] as List;
      final point = NavPoint(
        (c[1] as num).toDouble(),
        (c[0] as num).toDouble(),
      );
      if (!point.lat.isFinite ||
          !point.lon.isFinite ||
          point.lat.abs() > 90 ||
          point.lon.abs() > 180) {
        continue;
      }
      final street = [
        p['street'],
        p['housenumber'],
      ].whereType<String>().join(' ');
      final title =
          (p['name'] as String?) ??
          (street.isNotEmpty
              ? street
              : p['city'] as String? ??
                    p['postcode'] as String? ??
                    'Gekozen locatie');
      final parts = <String>{
        if (street.isNotEmpty && street != title) street,
        for (final k in ['postcode', 'city', 'district', 'country'])
          if (p[k] is String && p[k] != title) p[k],
      };
      final item = AddressResult(title, parts.join(', '), point);
      if (seen.add(item.label)) results.add(item);
    }
    return results;
  }

  @override
  Future<List<AddressResult>> search(String query, {NavPoint? focus}) async {
    query = query.trim();
    if (query.length < 3) return [];
    final key = jsonEncode([
      endpoint.toString(),
      query.toLowerCase(),
      focus?.lat.toStringAsFixed(2),
      focus?.lon.toStringAsFixed(2),
    ]);
    final raw = await database.getDocument('geocoder-cache', key);
    if (raw != null) {
      final j = jsonDecode(raw);
      if (DateTime.now().difference(DateTime.parse(j['time'])).inDays < 7) {
        cached = true;
        return (j['results'] as List)
            .map((r) => AddressResult.fromJson(Map<String, dynamic>.from(r)))
            .toList();
      }
    }
    cached = false;
    final data = await _fetch('/api/', {
      'q': query,
      'limit': '6',
      if (focus != null) 'lat': '${focus.lat}',
      if (focus != null) 'lon': '${focus.lon}',
    });
    // Use local OSM names: the public server does not offer Dutch lang=nl.
    final results = _parse(data);
    await database.putDocument(
      'geocoder-cache',
      key,
      jsonEncode({
        'time': DateTime.now().toIso8601String(),
        'results': results.map((r) => r.toJson()).toList(),
      }),
    );
    final cache = await database.documents('geocoder-cache');
    if (cache.length > 50) {
      final keys = cache.keys.toList()
        ..sort(
          (a, b) => (jsonDecode(cache[a]!)['time'] as String).compareTo(
            jsonDecode(cache[b]!)['time'],
          ),
        );
      for (final k in keys.take(cache.length - 50)) {
        await database.removeDocument('geocoder-cache', k);
      }
    }
    return results;
  }

  @override
  Future<AddressResult?> reverse(NavPoint point) async {
    final results = _parse(
      await _fetch('/reverse', {
        'lat': '${point.lat}',
        'lon': '${point.lon}',
        'limit': '1',
      }),
    );
    return results.firstOrNull;
  }

  @override
  void dispose() => client.close();
}
