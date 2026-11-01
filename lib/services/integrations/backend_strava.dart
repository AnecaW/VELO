import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:url_launcher/url_launcher.dart';

import '../accounts/account_service.dart';
import 'strava_service.dart';
import 'strava_integration.dart';
import 'integration_models.dart';

class BackendStravaService extends StravaService {
  final AccountService accounts;
  BackendStravaService(super.database, this.accounts);
  Future<void> refreshStatus() async {
    if (accounts.user == null) return;
    final info = await accounts.request('GET', '/api/v1/integrations/strava');
    if (info['status'] == 'needs_reconnect') {
      await StravaCache(database).expire(all: true);
    }
    await SyncRepository(database).update('strava', {
      'status': info['connected'] == true
          ? 'Verbonden'
          : info['status'] == 'needs_reconnect'
          ? 'Opnieuw verbinden'
          : 'Niet verbonden',
      'error': info['error'],
      if (info['last_sync'] != null)
        'lastSuccess': DateTime.fromMillisecondsSinceEpoch(
          (info['last_sync'] as int) * 1000,
          isUtc: true,
        ).toIso8601String(),
    });
    final jobs = await accounts.request('GET', '/api/v1/jobs') as List;
    for (final job in jobs.where((j) => j['kind'] == 'upload')) {
      await database.putDocument(
        'sync',
        job['job_key'],
        jsonEncode({
          'status': job['status'],
          'attempts': job['attempts'],
          'error': job['error'],
          'next': (job['next_at'] as int) * 1000,
          if (job['result']?['activity_id'] != null)
            'activity_id': job['result']['activity_id'],
        }),
      );
    }
    final history =
        await accounts.request('GET', '/api/v1/sync/history') as List;
    final expectedKeys = history
        .map((row) => 'server-${sha256.convert(utf8.encode(jsonEncode(row)))}')
        .toSet();
    for (final key in (await database.documents('sync-history')).keys) {
      if (key.startsWith('server-') && !expectedKeys.contains(key)) {
        await database.removeDocument('sync-history', key);
      }
    }
    for (final row in history) {
      final key = 'server-${sha256.convert(utf8.encode(jsonEncode(row)))}';
      await database.putDocument(
        'sync-history',
        key,
        jsonEncode({
          'provider': row['provider'],
          'date': DateTime.fromMillisecondsSinceEpoch(
            (row['created_at'] as int) * 1000,
            isUtc: true,
          ).toIso8601String(),
          'trigger': 'server',
          'status': row['status'],
          'message': row['message'],
        }),
      );
    }
  }

  @override
  Future<Map<String, dynamic>?> account() async {
    if (accounts.user == null) return null;
    final info = Map<String, dynamic>.from(
      await accounts.request('GET', '/api/v1/integrations/strava'),
    );
    return info['connected'] == true ? info : null;
  }

  @override
  Future<void> authorize(
    String base,
    String clientId, {
    List<String> scopes = const ['activity:read'],
  }) async {
    final state = base64UrlEncode(
      List.generate(32, (_) => Random.secure().nextInt(256)),
    ).replaceAll('=', '');
    final verifier = base64UrlEncode(
      List.generate(48, (_) => Random.secure().nextInt(256)),
    ).replaceAll('=', '');
    await store.write('strava-state', state);
    await store.write('strava-verifier', verifier);
    await store.write('strava-auth-started', now().toUtc().toIso8601String());
    final data = await accounts.request(
      'POST',
      '/api/v1/integrations/strava/authorize',
      body: {
        'state': state,
        'code_challenge': base64UrlEncode(
          sha256.convert(ascii.encode(verifier)).bytes,
        ).replaceAll('=', ''),
        'scopes': scopes,
      },
    );
    final uri = Uri.parse(data['authorization_url']);
    if (uri.scheme != 'https' ||
        uri.host != 'www.strava.com' ||
        uri.path != '/oauth/authorize' ||
        uri.queryParameters['state'] != state) {
      throw AccountFailure('Ongeldige autorisatiepagina.');
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw AccountFailure('Browser kan niet openen.');
    }
  }

  @override
  Future<void> handleCallback(Uri uri) async {
    final state = await store.read('strava-state'),
        verifier = await store.read('strava-verifier');
    final started = DateTime.tryParse(
      await store.read('strava-auth-started') ?? '',
    );
    if (uri.scheme != 'ultimatebike' ||
        uri.host != 'oauth' ||
        uri.path != '/strava' ||
        uri.hasFragment ||
        uri.queryParametersAll.values.any((v) => v.length != 1) ||
        state == null ||
        state != uri.queryParameters['state'] ||
        verifier == null ||
        started == null ||
        now().difference(started) > const Duration(minutes: 10)) {
      throw AccountFailure('Ongeldige of verlopen terugkeerlink.');
    }
    if (uri.queryParameters['error'] != null) {
      await cancelAuthorization();
      throw AccountFailure('Strava-toestemming geweigerd.');
    }
    await accounts.request(
      'POST',
      '/api/v1/integrations/strava/confirm',
      body: {
        'state': state,
        'handoff': uri.queryParameters['handoff'],
        'code_verifier': verifier,
      },
    );
    await cancelAuthorization();
    await store.write('strava-token', null);
  }

  @override
  Future<Set<String>> scopes() async =>
      ((await account())?['scope'] as String? ?? '').split(',').toSet();
  @override
  Future<String> accessToken({bool force = false}) async =>
      throw AccountFailure('Strava-tokens blijven op de server.');
  @override
  Future<void> disconnect() async {
    await accounts.request('DELETE', '/api/v1/integrations/strava');
    await StravaCache(database).expire(all: true);
  }

  @override
  Future<void> enqueue(String id) async {
    if (id.startsWith('strava:') ||
        await database.getDocument('activity-source', id) != null) {
      throw AccountFailure('Alleen eigen ritten kunnen worden geÃ¼pload.');
    }
    final raw = await database.getDocument('ride', id);
    if (raw == null) throw AccountFailure('GPS-spoor ontbreekt.');
    await accounts.request(
      'PUT',
      '/api/v1/data/rides/${Uri.encodeComponent(id)}',
      body: {'payload': jsonDecode(raw)},
    );
    await accounts.request(
      'POST',
      '/api/v1/integrations/strava/uploads/${Uri.encodeComponent(id)}',
    );
  }

  @override
  Future<void> sync() async {} // Server worker owns upload polling.
}

class BackendStravaIntegration extends StravaIntegration {
  BackendStravaIntegration(BackendStravaService super.service);
  AccountService get accounts => (service as BackendStravaService).accounts;
  @override
  Future<Map<String, dynamic>> details(int id) async {
    final raw = Map<String, dynamic>.from(
      await accounts.request(
        'GET',
        '/api/v1/integrations/strava/activities/$id',
      ),
    );
    final athlete = (await service.account())!['athlete']['id'] as int;
    await cache.activity(raw, athlete);
    return raw;
  }

  @override
  Future<bool> connected() async =>
      (await service.account())?['connected'] == true;
  @override
  Future<void> synchronize(
    SyncPreferences preferences, {
    bool reset = false,
  }) async {
    await accounts.request(
      'PUT',
      '/api/v1/integrations/strava/preferences',
      body: {
        for (final key in [
          'enabled',
          'automatic',
          'activities',
          'routes',
          'uploads',
        ])
          key: preferences.toJson()[key],
      },
    );
    final identity = accounts.user?['id'];
    final queued = await accounts.request(
      'POST',
      '/api/v1/integrations/strava/sync',
    );
    Map<String, dynamic>? job;
    for (var attempt = 0; attempt < 30; attempt++) {
      job = Map<String, dynamic>.from(
        await accounts.request('GET', '/api/v1/jobs/${queued['job_id']}'),
      );
      if (job['status'] != 'pending' && job['status'] != 'running') break;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    if (job?['status'] != 'complete' && job?['status'] != 'skipped') {
      throw IntegrationFailure(
        job?['error'] ?? 'Synchronisatie staat op de server ingepland. Probeer later opnieuw.',
      );
    }
    if (accounts.user?['id'] != identity) {
      throw AccountFailure('Account gewijzigd. Start synchronisatie opnieuw.');
    }
    await (service as BackendStravaService).refreshStatus();
    await cache.expire(all: true);
    final athlete = (await service.account())!['athlete']['id'] as int;
    if (preferences.activities) {
      final rows = await accounts.request(
        'GET',
        '/api/v1/integrations/strava/activities',
      ) as List;
      for (final row in rows) {
        await cache.activity(Map<String, dynamic>.from(row['data']), athlete);
      }
    }
    if (preferences.routes) {
      final rows = await accounts.request(
        'GET',
        '/api/v1/integrations/strava/routes',
      ) as List;
      for (final row in rows) {
        final data = row['data'];
        await cache.route('${data['id']}', data['gpx'], athlete);
      }
    }
  }
}
