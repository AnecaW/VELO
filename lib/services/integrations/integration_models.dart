import 'dart:convert';

import 'package:bike_computer/database/bike_computer_database.dart';

class IntegrationFailure implements Exception {
  final String message;
  final bool authentication;
  final Duration? retryAfter;
  const IntegrationFailure(
    this.message, {
    this.authentication = false,
    this.retryAfter,
  });
  @override
  String toString() => message;
}

class IntegrationPending extends IntegrationFailure {
  const IntegrationPending()
    : super(
        'Synchronisatie gaat op de achtergrond verder.',
        retryAfter: const Duration(seconds: 30),
      );
}

class SyncPreferences {
  final bool enabled,
      automatic,
      onOpen,
      afterRide,
      onNetwork,
      wifiOnly,
      activities,
      routes,
      uploads;
  const SyncPreferences({
    this.enabled = true,
    this.automatic = false,
    this.onOpen = true,
    this.afterRide = false,
    this.onNetwork = true,
    this.wifiOnly = false,
    this.activities = true,
    this.routes = false,
    this.uploads = false,
  });
  factory SyncPreferences.fromJson(Map<String, dynamic> j) => SyncPreferences(
    enabled: j['enabled'] ?? true,
    automatic: j['automatic'] ?? false,
    onOpen: j['onOpen'] ?? true,
    afterRide: j['afterRide'] ?? false,
    onNetwork: j['onNetwork'] ?? true,
    wifiOnly: j['wifiOnly'] ?? false,
    activities: j['activities'] ?? true,
    routes: j['routes'] ?? false,
    uploads: j['uploads'] ?? false,
  );
  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'automatic': automatic,
    'onOpen': onOpen,
    'afterRide': afterRide,
    'onNetwork': onNetwork,
    'wifiOnly': wifiOnly,
    'activities': activities,
    'routes': routes,
    'uploads': uploads,
  };
  SyncPreferences withValue(String key, bool value) =>
      SyncPreferences.fromJson({...toJson(), key: value});
}

class SyncRepository {
  final BikeComputerDatabase db;
  SyncRepository(this.db);
  Future<Map<String, dynamic>> state(String provider) async =>
      jsonDecode(await db.getDocument('integration-state', provider) ?? '{}');
  Future<void> update(String provider, Map<String, dynamic> values) async =>
      db.putDocument(
        'integration-state',
        provider,
        jsonEncode({...await state(provider), ...values}),
      );
  Future<SyncPreferences> preferences(String provider) async =>
      SyncPreferences.fromJson(
        jsonDecode(
          await db.getDocument('integration-preferences', provider) ?? '{}',
        ),
      );
  Future<void> savePreferences(String provider, SyncPreferences value) =>
      db.putDocument(
        'integration-preferences',
        provider,
        jsonEncode(value.toJson()),
      );
  Future<void> history(
    String provider,
    String trigger,
    String status,
    String message,
  ) async {
    final date = DateTime.now().toUtc();
    await db.putDocument(
      'sync-history',
      '$provider-${date.microsecondsSinceEpoch}',
      jsonEncode({
        'provider': provider,
        'date': date.toIso8601String(),
        'trigger': trigger,
        'status': status,
        'message': message,
      }),
    );
    final rows = await db.documents('sync-history');
    final keys = rows.keys.toList()..sort();
    for (final key in keys.take((keys.length - 100).clamp(0, keys.length))) {
      await db.removeDocument('sync-history', key);
    }
  }
}

abstract class IntegrationProvider {
  String get id;
  Future<bool> connected();
  Future<void> synchronize(SyncPreferences preferences, {bool reset = false});
  Future<void> disconnect();
}

class IntegrationInfo {
  final String id, name, description, availability, url;
  const IntegrationInfo(
    this.id,
    this.name,
    this.description,
    this.availability,
    this.url,
  );
}

class IntegrationRegistry {
  static const services = [
    IntegrationInfo(
      'strava',
      'Strava',
      'Recente activiteiten, routes en optionele rituploads.',
      'OAuth-backend en eigen client-ID vereist.',
      'https://developers.strava.com/docs/authentication/',
    ),
    IntegrationInfo(
      'komoot',
      'Komoot',
      'Routes via officiële GPX-export en bestaande GPX-import.',
      'Niet rechtstreeks beschikbaar: geen publieke API.',
      'https://support.komoot.com/hc/en-us/articles/10331570510618-komoot-API',
    ),
    IntegrationInfo(
      'garmin',
      'Garmin Connect',
      'Officieel ontwikkelaarsprogramma voor persoonlijke en zakelijke API-toegang.',
      'Eigen API-toegang vereist; adapter nog niet geïmplementeerd.',
      'https://developer.garmin.com/gc-developer-program/overview/',
    ),
    IntegrationInfo(
      'wahoo',
      'Wahoo',
      'Cloud API voor workouts en profielgegevens.',
      'Ontwikkelaarsgoedkeuring vereist; adapter nog niet geïmplementeerd.',
      'https://developers.wahooligan.com/cloud',
    ),
    IntegrationInfo(
      'rwgps',
      'Ride with GPS',
      'Officiële OAuth API voor routes en ritten.',
      'Eigen API-client vereist; adapter nog niet geïmplementeerd.',
      'https://ridewithgps.com/api',
    ),
    IntegrationInfo(
      'trainingpeaks',
      'TrainingPeaks',
      'Officiële partners-API voor trainingsgegevens.',
      'Alleen goedgekeurde ontwikkelaars; geen persoonlijke API-toegang.',
      'https://help.trainingpeaks.com/hc/en-us/articles/234441128-TrainingPeaks-API',
    ),
    IntegrationInfo(
      'health',
      'Health Connect',
      'Android-gezondheidsgegevens met afzonderlijke systeemtoestemming.',
      'Nog geen gegevensadapter in deze build; er worden geen gezondheidsgegevens gelezen.',
      'https://developer.android.com/health-and-fitness/health-connect',
    ),
    IntegrationInfo(
      'apple',
      'Apple Health',
      'HealthKit vereist iOS, entitlement en gegevenstoestemming.',
      'Niet beschikbaar op Android; geen HealthKit-adapter in deze build.',
      'https://developer.apple.com/documentation/healthkit',
    ),
    IntegrationInfo(
      'fit',
      'Google Fit',
      'Google verwijst nieuwe Android-integraties naar Health Connect.',
      'Geen nieuwe Google Fit-koppeling aangeboden.',
      'https://developer.android.com/health-and-fitness/health-connect/migration/fit',
    ),
  ];
}
