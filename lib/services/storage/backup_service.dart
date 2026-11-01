import 'package:bike_computer/services/training/training_generator.dart';

import 'dart:convert';

import 'package:bike_computer/database/bike_computer_database.dart';
import 'package:bike_computer/services/ride/session_codec.dart';
import 'package:bike_computer/services/ride/ride_history_service.dart';
import 'package:bike_computer/services/navigation/gpx_route.dart';

class BackupService {
  final BikeComputerDatabase database;
  BackupService(this.database);
  Future<String> export() async {
    final settings = await database.documents('settings');
    if (settings['app'] != null) {
      final values = jsonDecode(settings['app']!) as Map<String, dynamic>;
      values.remove('offlineMap');
      values.remove('offlineView');
      values.remove('mapOffline');
      settings['app'] = jsonEncode(values);
    }
    return jsonEncode({
      'version': 1,
      'rides': await database.documents('ride'),
      'routes': Map.fromEntries(
        (await database.documents('routes')).entries
            .where((e) => !e.key.startsWith('strava:')),
      ),
      'settings': settings,
      'names': await database.documents('ride-name'),
      'nutrition': await database.documents('nutrition'),
      'trainingPlans': await database.documents('training-plans'),
      'trainingProfile': await database.documents('training-profile'),
      'trainingResults': await database.documents('training-results'),
      'activityProfiles': await database.documents('profiles'),
    });
  }

  Future<void> restore(String raw) async {
    if (utf8.encode(raw).length > 50 * 1024 * 1024) {
      throw const FormatException('Back-up maximaal 50 MB');
    }
    final j = jsonDecode(raw) as Map<String, dynamic>;
    if (j['version'] != 1) {
      throw const FormatException('Onbekend back-upformaat');
    }
    final rides = (j['rides'] as Map).cast<String, String>();
    final routes = (j['routes'] as Map).cast<String, String>();
    // Validate every payload before writing any data.
    final sessions = rides.values.map(SessionCodec.decode).toList();
    for (final s in sessions) {
      if (s.id == null ||
          !s.totalDistance.isFinite ||
          s.totalDistance < 0 ||
          s.elapsedTime.isNegative) {
        throw const FormatException('Ongeldige rit');
      }
      for (final p in s.trackPoints) {
        if (!p.latitude.isFinite ||
            !p.longitude.isFinite ||
            p.latitude.abs() > 90 ||
            p.longitude.abs() > 180) {
          throw const FormatException('Ongeldig GPS-punt');
        }
      }
    }
    for (final r in routes.values) {
      final parsed = NavRoute.decode(r);
      if (parsed.points.length < 2 ||
          parsed.points.any(
            (p) =>
                !p.lat.isFinite ||
                !p.lon.isFinite ||
                p.lat.abs() > 90 ||
                p.lon.abs() > 180,
          )) {
        throw const FormatException('Ongeldige route');
      }
    }
    final settings = (j['settings'] as Map).cast<String, String>();
    for (final s in settings.values) {
      final decoded = jsonDecode(s);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Ongeldige instellingen');
      }
      for (final e in decoded.entries) {
        if (e.key.startsWith('fields-') &&
            (e.value is! List || (e.value as List).any((v) => v is! String))) {
          throw const FormatException('Ongeldige gegevensvelden');
        }
      }
    }
    if (settings['app'] != null) {
      final values = jsonDecode(settings['app']!) as Map<String, dynamic>;
      values.remove('offlineMap');
      values.remove('offlineView');
      values.remove('mapOffline');
      final local = await database.getDocument('settings', 'app');
      if (local != null) {
        final old = jsonDecode(local);
        if (old['offlineMap'] != null) values['offlineMap'] = old['offlineMap'];
      }
      settings['app'] = jsonEncode(values);
    }
    for (final raw in (j['trainingPlans'] as Map? ?? {}).values) {
      TrainingPlan.decode(raw).validate();
    }
    for (final raw in (j['trainingProfile'] as Map? ?? {}).values) {
      TrainingProfile.fromJson(jsonDecode(raw)).validate();
    }
    for (final raw in (j['trainingResults'] as Map? ?? {}).values) {
      final result = jsonDecode(raw);
      if (result['name'] is! String ||
          result['seconds'] is! int ||
          result['seconds'] < 0 ||
          result['measurements'] is! List ||
          DateTime.tryParse(result['started'] ?? '') == null) {
        throw const FormatException('Ongeldig trainingsresultaat');
      }
    }
    for (final raw in (j['activityProfiles'] as Map? ?? {}).values) {
      final list = jsonDecode(raw);
      if (list is! List || list.isEmpty) {
        throw const FormatException('Ongeldige activiteitprofielen');
      }
      for (final p in list) {
        if (p is! Map ||
            p['id'] is! String ||
            p['name'] is! String ||
            p['type'] is! String ||
            p['accent'] is! int ||
            p['autoPause'] is! bool ||
            p['pauseSpeed'] is! num ||
            !(p['pauseSpeed'] as num).isFinite ||
            p['pauseSpeed'] < 0) {
          throw const FormatException('Ongeldig activiteitprofiel');
        }
      }
    }
    await database.transaction(() async {
      final checkpoint = await database.getDocument('active', 'ride');
      for (final s in sessions) {
        await RideHistoryService(database: database).saveRide(s);
      }
      // Importing an archive must never delete an in-progress local ride.
      if (checkpoint != null) {
        await database.putDocument('active', 'ride', checkpoint);
      }
      for (final e in routes.entries) {
        await database.putDocument('routes', e.key, e.value);
      }
      for (final e in settings.entries) {
        await database.putDocument('settings', e.key, e.value);
      }
      for (final pair in [
        ('names', 'ride-name'),
        ('nutrition', 'nutrition'),
        ('trainingPlans', 'training-plans'),
        ('trainingProfile', 'training-profile'),
        ('trainingResults', 'training-results'),
        ('activityProfiles', 'profiles'),
      ]) {
        for (final e in (j[pair.$1] as Map? ?? {}).entries) {
          if (e.key is String && e.value is String) {
            await database.putDocument(pair.$2, e.key, e.value);
          }
        }
      }
    });
  }
}
