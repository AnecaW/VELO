import 'dart:convert';

import 'package:bike_computer/database/bike_computer_database.dart';
import 'package:bike_computer/services/navigation/gpx_route.dart';

import 'integration_models.dart';
import 'strava_service.dart';

/// Provider data is a bounded, private cache, never a local recorded ride.
class StravaCache {
  final BikeComputerDatabase db;
  final DateTime Function() now;
  StravaCache(this.db, {DateTime Function()? now}) : now = now ?? DateTime.now;
  Future<void> activity(Map<String, dynamic> raw, int athlete) async {
    for (final key in ['id', 'distance', 'moving_time', 'elapsed_time']) {
      if (raw[key] is! num || !(raw[key] as num).isFinite || raw[key] < 0) {
        throw const FormatException(
          'Strava-activiteit mist geldige afstand, tijd of ID',
        );
      }
    }
    if (raw['id'] is! int ||
        DateTime.tryParse(raw['start_date'] ?? '') == null) {
      throw const FormatException('Strava-activiteit mist starttijd of ID');
    }
    // Uploaded local rides already appear in the local history. Do not duplicate them.
    for (final job in (await db.documents('sync')).values) {
      if (jsonDecode(job)['activity_id'] == raw['id']) return;
    }
    await db.putDocument(
      'strava-activities',
      '$athlete:${raw['id']}',
      jsonEncode({
        'source': 'Strava',
        'athlete': athlete,
        'synced': now().toUtc().toIso8601String(),
        'expires': now()
            .add(const Duration(hours: 24))
            .toUtc()
            .toIso8601String(),
        'data': raw,
      }),
    );
  }

  Future<void> route(String id, String gpx, int athlete) async {
    final route = parseGpx(gpx), key = 'strava:$athlete:$id';
    final metadata = {
      'source': 'Strava',
      'athlete': athlete,
      'id': id,
      'synced': now().toUtc().toIso8601String(),
      'expires': now().add(const Duration(hours: 24)).toUtc().toIso8601String(),
    };
    await db.transaction(() async {
      await db.putDocument('routes', key, route.encode());
      await db.putDocument('route-source', key, jsonEncode(metadata));
      await db.putDocument('strava-route-original', key, gpx);
    });
  }

  Future<void> expire({bool all = false}) async {
    for (final row in (await db.documents('strava-activities')).entries) {
      final expiry = DateTime.tryParse(jsonDecode(row.value)['expires'] ?? '');
      if (all || expiry == null || !expiry.isAfter(now())) {
        await db.removeDocument('strava-activities', row.key);
      }
    }
    for (final row in (await db.documents('route-source')).entries) {
      final meta = jsonDecode(row.value);
      if (meta['source'] != 'Strava') continue;
      final expiry = DateTime.tryParse(meta['expires'] ?? '');
      if (all || expiry == null || !expiry.isAfter(now())) {
        final selected = await db.getDocument('navigation', 'selected');
        final route = await db.getDocument('routes', row.key);
        final source = await db.getDocument('navigation', 'source');
        if (selected != null && selected == route && source == row.key) {
          await db.removeDocument('navigation', 'selected');
          await db.removeDocument('navigation', 'source');
        }
        await db.removeDocument('routes', row.key);
        await db.removeDocument('route-source', row.key);
        await db.removeDocument('strava-route-original', row.key);
      }
    }
  }
}

class StravaIntegration implements IntegrationProvider {
  final StravaService service;
  late final repository = SyncRepository(service.database),
      cache = StravaCache(service.database, now: service.now);
  StravaIntegration(this.service);
  @override
  String get id => 'strava';
  @override
  Future<bool> connected() async =>
      (await service.account())?['athlete']?['id'] is int &&
      await service.store.read('strava-reconnect') != 'true';
  Future<int> get _athlete async {
    final id = (await service.account())?['athlete']?['id'];
    if (id is! int) {
      throw const IntegrationFailure(
        'Accountgegevens ontbreken. Verbind Strava opnieuw.',
        authentication: true,
      );
    }
    return id;
  }

  @override
  Future<void> synchronize(
    SyncPreferences preferences, {
    bool reset = false,
  }) async {
    await cache.expire();
    final scopes = await service.scopes(), athlete = await _athlete;
    final checkpoint = await repository.state(id), now = service.now();
    if (preferences.activities) {
      if (!scopes.contains('activity:read') &&
          !scopes.contains('activity:read_all')) {
        throw const IntegrationFailure(
          'Activiteiten lezen is niet toegestaan. Verbind opnieuw met leesrechten.',
        );
      }
      final cursor = reset
          ? null
          : DateTime.tryParse(checkpoint['cursor'] ?? '');
      final full =
          reset ||
          DateTime.tryParse(checkpoint['fullRefresh'] ?? '') == null ||
          now.difference(DateTime.parse(checkpoint['fullRefresh'])) >
              const Duration(hours: 20);
      final after = full || cursor == null
          ? now.subtract(const Duration(days: 7))
          : cursor.subtract(const Duration(minutes: 5));
      final before = now.millisecondsSinceEpoch ~/ 1000;
      var complete = false;
      for (var page = 1; page <= 4; page++) {
        final response = await service.api(
          'athlete/activities',
          query: {
            'after': '${after.millisecondsSinceEpoch ~/ 1000}',
            'before': '$before',
            'page': '$page',
            'per_page': '50',
          },
        );
        final rows = jsonDecode(response.body);
        if (rows is! List) {
          throw const FormatException('Ongeldige Strava-activiteitenlijst');
        }
        if (!await connected()) {
          throw const IntegrationFailure(
            'Account niet meer verbonden.',
            authentication: true,
          );
        }
        for (final raw in rows) {
          if (raw is! Map<String, dynamic>) {
            throw const FormatException('Ongeldige activiteit');
          }
          await cache.activity(raw, athlete);
        }
        if (rows.length < 50) {
          complete = true;
          break;
        }
      }
      if (!complete) {
        throw const IntegrationFailure(
          'Te veel activiteiten voor één beperkte synchronisatie. Verklein de periode of probeer later; de cursor is niet vooruitgezet.',
        );
      }
      await repository.update(id, {
        'cursor': now.toUtc().toIso8601String(),
        if (full) 'fullRefresh': now.toUtc().toIso8601String(),
      });
    }
    if (preferences.routes) {
      if (!scopes.contains('read') && !scopes.contains('read_all')) {
        throw const IntegrationFailure(
          'Routes lezen vereist aanvullende Strava-toestemming. Verbind opnieuw.',
        );
      }
      // Small bounded cache; not a bulk exporter.
      final response = await service.api(
        'athletes/$athlete/routes',
        query: {'page': '1', 'per_page': '10'},
      );
      final rows = jsonDecode(response.body);
      if (rows is! List) {
        throw const FormatException('Ongeldige Strava-routelijst');
      }
      for (final raw in rows) {
        final routeId = raw['id_str'] ?? raw['id']?.toString();
        if (routeId == null || !RegExp(r'^\d+$').hasMatch(routeId)) {
          throw const FormatException('Ongeldige route-ID');
        }
        final export = await service.api('routes/$routeId/export_gpx');
        if (!await connected()) {
          throw const IntegrationFailure(
            'Account ontkoppeld.',
            authentication: true,
          );
        }
        if (export.statusCode == 404) {
          await service.database.removeDocument(
            'routes',
            'strava:$athlete:$routeId',
          );
          continue;
        }
        await cache.route(routeId, export.body, athlete);
      }
    }
    if (preferences.uploads) {
      if (!scopes.contains('activity:write')) {
        throw const IntegrationFailure(
          'Uploaden vereist aanvullende Strava-toestemming.',
        );
      }
      await service.sync();
      final jobs = (await service.database.documents('sync')).values
          .map((j) => jsonDecode(j));
      if (jobs.any((j) => j['status'] != 'complete')) {
        throw const IntegrationFailure(
          'Er staan uploads in de wachtrij. Bekijk de status; onzekere uploads worden nooit blind herhaald.',
          retryAfter: Duration(minutes: 5),
        );
      }
    }
  }

  Future<Map<String, dynamic>> details(int id) async {
    final p = await repository.preferences('strava');
    if (!p.enabled || !p.activities) {
      throw const IntegrationFailure(
        'Activiteiten lezen staat uit in Privacy & Synchronisatie.',
      );
    }
    final response = await service.api('activities/$id');
    final athlete = await _athlete;
    if (response.statusCode == 404) {
      await service.database.removeDocument(
        'strava-activities',
        '$athlete:$id',
      );
      throw const IntegrationFailure(
        'Deze activiteit bestaat niet meer op Strava.',
      );
    }
    final raw = jsonDecode(response.body) as Map<String, dynamic>;
    if (!await connected()) {
      throw const IntegrationFailure(
        'Account ontkoppeld.',
        authentication: true,
      );
    }
    await cache.activity(raw, athlete);
    return raw;
  }

  @override
  Future<void> disconnect() async {
    try {
      await service.disconnect();
    } finally {
      await cache.expire(all: true);
      await repository.savePreferences(
        id,
        const SyncPreferences(enabled: false),
      );
      await service.database.removeDocument('integration-state', id);
      for (final job in (await service.database.documents('sync')).keys) {
        await service.database.removeDocument('sync', job);
      }
      for (final row in (await service.database.documents(
        'sync-history',
      )).entries) {
        if (jsonDecode(row.value)['provider'] == id) {
          await service.database.removeDocument('sync-history', row.key);
        }
      }
    }
  }
}
