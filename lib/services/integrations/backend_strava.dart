import 'sync_engine.dart';

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
  BackendStravaService(super.db, this.accounts, {super.openUrl})
    : super(store: accounts.store);
  bool _flushing = false;
  Map<String, dynamic>? _information;
  DateTime? _informationAt;
  String? _informationOwner;
  Future<Map<String, dynamic>>? _informationRequest;
  String? _requestOwner;
  void ensureOwner(String? owner) {
    if (owner == null || accounts.user?['id'] != owner) {
      throw AccountFailure('Account gewijzigd. Probeer opnieuw.');
    }
  }

  Future<T> ownedWrite<T>(String owner, Future<T> Function() action) =>
      database.transaction(() async {
        ensureOwner(owner);
        if (await database.getDocument('account-owner', 'current') != owner) {
          throw AccountFailure('Account gewijzigd.');
        }
        return action();
      });
  void invalidateStatus() {
    _information = null;
    _informationAt = null;
    _informationOwner = null;
  }

  Future<void> queueAfterRide(String id) async {
    final owner = accounts.user?['id'];
    if (owner == null) return;
    await database.putDocument(
      'strava-upload-outbox',
      jsonEncode([owner, id]),
      jsonEncode({'owner': owner, 'ride': id, 'automatic': true}),
    );
  }

  /// A local save never waits for Strava. Only acknowledged, idempotent jobs
  /// leave this owner-bound outbox; network failures remain queued.
  Future<void> flushOutbox() async {
    if (_flushing || accounts.user == null) return;
    _flushing = true;
    try {
      final owner = accounts.user!['id'];
      final pending = (await database.documents('strava-upload-outbox')).entries
          .where((e) => jsonDecode(e.value)['owner'] == owner)
          .toList();
      if (pending.isEmpty) return;
      final preferences = await SyncRepository(database).preferences('strava');
      if (!preferences.enabled || (await account()) == null) return;
      for (final row in pending) {
        if (accounts.user?['id'] != owner) return;
        final item = jsonDecode(row.value);
        final automatic = item['automatic'] != false;
        if (automatic &&
            (!preferences.uploads ||
                !preferences.automatic ||
                !preferences.afterRide)) {
          continue;
        }
        final id = item['ride'] as String;
        if (await database.getDocument('ride', id) == null) continue;
        await _send(id, automatic: automatic);
        await database.removeDocument('strava-upload-outbox', row.key);
      }
    } catch (_) {
      // Retry on network/lifecycle/background events without exposing tokens.
    } finally {
      _flushing = false;
    }
  }

  Future<Map<String, dynamic>> information({bool refresh = false}) async {
    if (accounts.user == null) {
      return {
        'configured': false,
        'connected': false,
        'status': 'login_required',
      };
    }
    final owner = accounts.user!['id'] as String;
    if (!refresh &&
        _informationOwner == owner &&
        _information != null &&
        _informationAt != null &&
        DateTime.now().difference(_informationAt!) <
            const Duration(seconds: 5)) {
      return _information!;
    }
    if (_informationRequest != null && _requestOwner == owner) {
      return _informationRequest!;
    }
    final request = () async {
      final result = Map<String, dynamic>.from(
        await accounts.request('GET', '/api/v1/integrations/strava'),
      );
      ensureOwner(owner);
      _informationOwner = owner;
      _information = result;
      _informationAt = DateTime.now();
      return result;
    }();
    _informationRequest = request;
    _requestOwner = owner;
    try {
      return await request;
    } finally {
      if (identical(_informationRequest, request)) {
        _informationRequest = null;
        _requestOwner = null;
      }
    }
  }

  Future<void> refreshStatus() async {
    final owner = accounts.user?['id'] as String?;
    if (owner == null) return;
    final info = await information(refresh: true);
    final jobs =
        info['jobs'] as List? ??
        await accounts.request('GET', '/api/v1/jobs') as List;
    final history =
        info['history'] as List? ??
        await accounts.request('GET', '/api/v1/sync/history') as List;
    await ownedWrite(owner, () async {
      if (info['status'] == 'needs_reconnect') {
        await StravaCache(database).expire(all: true);
      }
      await SyncRepository(database).update('strava', {
        'status': info['configured'] == false
            ? 'Configuratie ontbreekt'
            : ['pending', 'running'].contains(info['sync_status'])
            ? 'Synchronisatie bezig'
            : info['sync_status'] == 'failed'
            ? 'Synchronisatie mislukt'
            : info['connected'] == true
            ? 'Verbonden'
            : info['status'] == 'needs_reconnect'
            ? 'Verbinden vereist'
            : 'Niet verbonden',
        'error': info['error'] ?? info['sync_error'],
        if (info['last_sync'] != null)
          'lastSuccess': DateTime.fromMillisecondsSinceEpoch(
            (info['last_sync'] as int) * 1000,
            isUtc: true,
          ).toIso8601String(),
      });
      final ids = jobs
          .where((j) => j['kind'] == 'upload')
          .map((j) => j['job_key'])
          .toSet();
      for (final key in (await database.documents('sync')).keys) {
        if (!ids.contains(key)) await database.removeDocument('sync', key);
      }
      for (final job in jobs.where((j) => j['kind'] == 'upload')) {
        await database.putDocument(
          'sync',
          job['job_key'],
          jsonEncode({
            'job_id': job['id'],
            'status': job['status'],
            'attempts': job['attempts'],
            'error': job['error'],
            'next': (job['next_at'] as int) * 1000,
            'upload_id': job['result']?['upload_id'],
            'previously_submitted': job['result']?['previously_submitted'],
            'removed': job['result']?['removed'],
            if (job['result']?['activity_id'] != null)
              'activity_id': job['result']['activity_id'],
          }),
        );
      }
      final expected = history
          .map((r) => 'server-${sha256.convert(utf8.encode(jsonEncode(r)))}')
          .toSet();
      for (final key in (await database.documents('sync-history')).keys) {
        if (key.startsWith('server-') && !expected.contains(key)) {
          await database.removeDocument('sync-history', key);
        }
      }
      for (final row in history) {
        await database.putDocument(
          'sync-history',
          'server-${sha256.convert(utf8.encode(jsonEncode(row)))}',
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
    });
  }

  Future<void> refreshRideStatus(String id) async {
    final owner = accounts.user?['id'] as String?;
    if (owner == null) return;
    final rows = await accounts.request(
      'GET',
      '/api/v1/jobs?ride_id=${Uri.encodeQueryComponent(id)}',
    ) as List;
    await ownedWrite(owner, () async {
      if (rows.isEmpty) return;
      final job = rows.first;
      await database.putDocument(
        'sync',
        id,
        jsonEncode({
          'job_id': job['id'],
          'status': job['status'],
          'error': job['error'],
          'upload_id': job['result']?['upload_id'],
          'activity_id': job['result']?['activity_id'],
          'removed': job['result']?['removed'],
          'previously_submitted': job['result']?['previously_submitted'],
        }),
      );
    });
  }

  @override
  Future<Map<String, dynamic>?> account() async {
    if (accounts.user == null) return null;
    final info = await information();
    return info['connected'] == true ? info : null;
  }

  @override
  Future<void> authorize(
    String base,
    String clientId, {
    List<String> scopes = const ['activity:read'],
  }) async {
    if (await database.getDocument('integration-preferences', 'strava') ==
        null) {
      await SyncRepository(database)
          .savePreferences('strava', const SyncPreferences());
    }
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
        'platform': 'android',
      },
    );
    final uri = Uri.parse(data['authorization_url']);
    if (uri.scheme != 'https' ||
        uri.host != 'www.strava.com' ||
        !['/oauth/mobile/authorize', '/oauth/authorize'].contains(uri.path) ||
        uri.queryParameters['state'] != state) {
      throw AccountFailure('Ongeldige autorisatiepagina.');
    }
    if (!await (openUrl?.call(uri) ??
        launchUrl(uri, mode: LaunchMode.externalApplication))) {
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
      throw AccountFailure(
        uri.queryParameters['error'] == 'denied'
            ? 'Strava-toestemming geweigerd. Je kunt opnieuw verbinden.'
            : 'De Strava-koppeling kon niet worden afgerond. Probeer opnieuw.',
      );
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
    final preferences = await SyncRepository(database).preferences('strava');
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
    await cancelAuthorization();
    await store.write('strava-token', null);
    invalidateStatus();
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
    await cancelAuthorization();
    invalidateStatus();
    await StravaCache(database).expire(all: true);
    for (final row in (await database.documents(
      'strava-upload-outbox',
    )).entries) {
      if (jsonDecode(row.value)['owner'] == accounts.user?['id']) {
        await database.removeDocument('strava-upload-outbox', row.key);
      }
    }
  }

  @override
  Future<void> enqueue(String id) async {
    await _validate(id);
    final owner = accounts.user?['id'];
    if (owner == null) throw AccountFailure('Meld je eerst aan bij VELO.');
    final key = jsonEncode([owner, id]);
    await database.putDocument(
      'strava-upload-outbox',
      key,
      jsonEncode({'owner': owner, 'ride': id, 'automatic': false}),
    );
    await _send(id, automatic: false);
    await database.removeDocument('strava-upload-outbox', key);
  }

  Future<Map<String, dynamic>> _validate(String id) async {
    if (id.startsWith('strava:') ||
        await database.getDocument('activity-source', id) != null) {
      throw AccountFailure(
        'Alleen je eigen opgenomen ritten kunnen worden geüpload.',
      );
    }
    final raw = await database.getDocument('ride', id);
    if (raw == null) throw AccountFailure('De opgeslagen rit ontbreekt.');
    final payload = jsonDecode(raw) as Map<String, dynamic>;
    final points = payload['points'];
    if (points is! List || points.length < 2) {
      throw AccountFailure(
        'Deze rit heeft geen bruikbaar GPS-spoor. Minimaal twee punten met tijdstempels zijn nodig.',
      );
    }
    var previous = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    for (final point in points) {
      final time = point is List && point.length > 3
          ? DateTime.tryParse(point[3].toString())
          : null;
      if (time == null ||
          !time.isAfter(previous) ||
          point[0] is! num ||
          point[1] is! num ||
          !(point[0] as num).isFinite ||
          !(point[1] as num).isFinite ||
          (point[0] as num).abs() > 90 ||
          (point[1] as num).abs() > 180) {
        throw AccountFailure(
          'Het GPS-spoor bevat ongeldige punten of tijdstempels.',
        );
      }
      previous = time;
    }
    return payload;
  }

  Future<void> _send(String id, {required bool automatic}) async {
    final preferences = await SyncRepository(database).preferences('strava');
    if (preferences.wifiOnly && !(await NetworkState.current()).wifi) {
      throw AccountFailure(
        'Wacht op wifi. Je rit blijft in de lokale wachtrij.',
      );
    }
    final owner = accounts.user?['id'] as String?;
    final payload = await _validate(id);
    ensureOwner(owner);
    if (owner == null) throw AccountFailure('Meld je eerst aan bij VELO.');
    final meta = jsonDecode(
      await database.getDocument(
            'account-sync-meta',
            jsonEncode([owner, 'ride', id]),
          ) ??
          '{}',
    );
    await accounts.request(
      'PUT',
      '/api/v1/data/rides/${Uri.encodeComponent(id)}',
      body: {
        'payload': payload,
        if (meta['revision'] != null) 'expected_revision': meta['revision'],
      },
    );
    ensureOwner(owner);
    await accounts.request(
      'POST',
      '/api/v1/integrations/strava/uploads/${Uri.encodeComponent(id)}',
      body: {'automatic': automatic},
    );
    invalidateStatus();
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

  Future<void> loadCached() async {
    final backend = service as BackendStravaService;
    final owner = accounts.user?['id'] as String?;
    if (owner == null) return;
    final info = await backend.information();
    if (info['connected'] != true) {
      await backend.ownedWrite(owner, () => cache.expire(all: true));
      return;
    }
    final athlete = info['athlete']['id'] as int,
        values = <Map<String, dynamic>>[];
    var page = 1;
    do {
      final result = await accounts.request(
        'GET',
        '/api/v1/integrations/strava/activities?page=$page',
      );
      for (final row in result['items'] as List) {
        values.add(Map<String, dynamic>.from(row));
      }
      page = result['next_page'] as int? ?? 0;
    } while (page > 0);
    final routes = await accounts.request(
      'GET',
      '/api/v1/integrations/strava/routes',
    ) as List;
    await backend.ownedWrite(owner, () async {
      await cache.expire();
      final expected = values.map((v) => '$athlete:${v['data']['id']}').toSet();
      for (final key in (await service.database.documents(
        'strava-activities',
      )).keys) {
        if (!expected.contains(key)) {
          await service.database.removeDocument('strava-activities', key);
        }
      }
      DateTime? expiry(Map row) => row['expires_at'] is num
          ? DateTime.fromMillisecondsSinceEpoch(
              (row['expires_at'] as num).toInt() * 1000,
              isUtc: true,
            )
          : null;
      for (final row in values) {
        await cache.activity(
          Map<String, dynamic>.from(row['data']),
          athlete,
          expiresAt: expiry(row),
        );
      }
      for (final row in routes) {
        final d = row['data'];
        await cache.route(
          '${d['id']}',
          d['gpx'],
          athlete,
          expiresAt: expiry(row),
        );
      }
    });
  }

  @override
  Future<bool> connected() async =>
      (await service.account())?['connected'] == true;
  @override
  Future<void> synchronize(
    SyncPreferences preferences, {
    bool reset = false,
  }) async {
    if (reset) {
      await accounts.request('DELETE', '/api/v1/integrations/strava/cache');
    }
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
    for (var attempt = 0; attempt < 6; attempt++) {
      job = Map<String, dynamic>.from(
        await accounts.request('GET', '/api/v1/jobs/${queued['job_id']}'),
      );
      if (job['status'] != 'pending' && job['status'] != 'running') break;
      await Future<void>.delayed(Duration(seconds: attempt < 2 ? 2 : 5));
    }
    if (['pending', 'running'].contains(job?['status'])) {
      throw const IntegrationPending();
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
    await loadCached();
  }
}
