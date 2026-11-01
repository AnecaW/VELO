import 'dart:convert';
import 'dart:math';
import 'dart:io' show HttpDate;

import 'package:crypto/crypto.dart';

import 'integration_models.dart';

import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:bike_computer/database/bike_computer_database.dart';
import 'package:bike_computer/services/ride/session_codec.dart';
import 'package:bike_computer/services/ride/gpx_export_service.dart';

abstract class TokenStore {
  Future<String?> read(String key);
  Future<void> write(String key, String? value);
}

class SecureTokenStore implements TokenStore {
  final storage = const FlutterSecureStorage();
  @override
  Future<String?> read(String key) => storage.read(key: key);
  @override
  Future<void> write(String key, String? value) => value == null
      ? storage.delete(key: key)
      : storage.write(key: key, value: value);
}

class StravaService {
  final BikeComputerDatabase database;
  final TokenStore store;
  final http.Client client;
  final DateTime Function() now;
  final Future<bool> Function(Uri)? openUrl;
  static bool _syncing = false;
  Future<String>? _refresh;
  StravaService(
    this.database, {
    TokenStore? store,
    http.Client? client,
    DateTime Function()? now,
    this.openUrl,
  }) : store = store ?? SecureTokenStore(),
       client = client ?? http.Client(),
       now = now ?? DateTime.now;
  Future<void> authorize(
    String base,
    String clientId, {
    List<String> scopes = const ['activity:read'],
  }) async {
    final uri = Uri.parse(base);
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw ArgumentError('OAuth-backend vereist een HTTPS URL');
    }
    if (int.tryParse(clientId) == null) {
      throw ArgumentError('Vul je Strava client ID in');
    }
    final state = base64Url.encode(
      List.generate(32, (_) => Random.secure().nextInt(256)),
    );
    final verifier = base64Url
        .encode(List.generate(48, (_) => Random.secure().nextInt(256)))
        .replaceAll('=', '');
    final challenge = base64Url
        .encode(sha256.convert(ascii.encode(verifier)).bytes)
        .replaceAll('=', '');
    await store.write('strava-base', base.replaceAll(RegExp(r'/+$'), ''));
    await store.write('strava-state', state);
    await store.write('strava-verifier', verifier);
    await store.write('strava-auth-started', now().toUtc().toIso8601String());
    try {
      final response = await client
          .post(
            Uri.parse('${await store.read('strava-base')}/start'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'client_id': clientId,
              'state': state,
              'code_challenge': challenge,
              'scopes': scopes,
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw const IntegrationFailure(
          'OAuth-backend niet beschikbaar of client-ID niet geconfigureerd.',
        );
      }
      final auth = Uri.parse(jsonDecode(response.body)['authorization_url']);
      if (auth.scheme != 'https' ||
          auth.host != 'www.strava.com' ||
          auth.path != '/oauth/authorize' ||
          auth.queryParameters['state'] != state ||
          auth.queryParameters['client_id'] != clientId) {
        throw const FormatException(
          'Backend leverde geen geldige Strava-autorisatiepagina',
        );
      }
      final opened = openUrl == null
          ? await launchUrl(auth, mode: LaunchMode.externalApplication)
          : await openUrl!(auth);
      if (!opened) {
        throw StateError('Browser kan niet worden geopend');
      }
    } catch (_) {
      await cancelAuthorization();
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _backend(
    String path,
    Map<String, dynamic> body,
  ) async {
    final base = await store.read('strava-base');
    if (base == null || !base.startsWith('https://')) {
      throw StateError('Configureer eerst je OAuth-backend');
    }
    final response = await client
        .post(
          Uri.parse('$base/$path'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 25));
    if (response.statusCode == 400 ||
        response.statusCode == 401 ||
        response.statusCode == 403) {
      throw const IntegrationFailure(
        'Strava-toestemming verlopen of ingetrokken. Verbind je account opnieuw.',
        authentication: true,
      );
    }
    if (response.statusCode != 200) {
      throw StateError('OAuth-verzoek mislukt (HTTP ${response.statusCode})');
    }
    Map<String, dynamic> token;
    try {
      token = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw const IntegrationFailure('Ongeldig antwoord van de OAuth-backend.');
    }
    if (token['access_token'] is! String ||
        token['refresh_token'] is! String ||
        token['expires_at'] is! num) {
      throw const FormatException('Ongeldig OAuth-antwoord');
    }
    return token;
  }

  Future<void> exchange(String code) async {
    throw const IntegrationFailure(
      'Handmatige codes worden niet meer gebruikt. Kies Connect with Strava.',
    );
  }

  Future<void> handleCallback(Uri uri) async {
    if (uri.scheme != 'ultimatebike' ||
        uri.host != 'oauth' ||
        uri.path != '/strava' ||
        uri.hasFragment ||
        uri.queryParametersAll.values.any((v) => v.length != 1)) {
      throw const IntegrationFailure('Ongeldige OAuth-terugkeerlink.');
    }
    final state = await store.read('strava-state'),
        verifier = await store.read('strava-verifier');
    final started = DateTime.tryParse(
      await store.read('strava-auth-started') ?? '',
    );
    if (state == null ||
        state != uri.queryParameters['state'] ||
        verifier == null ||
        started == null ||
        now().difference(started) > const Duration(minutes: 10)) {
      throw const IntegrationFailure(
        'OAuth-terugkeer is verlopen of hoort niet bij deze telefoon. Start opnieuw.',
      );
    }
    if (uri.queryParameters['error'] != null) {
      await cancelAuthorization();
      throw const IntegrationFailure(
        'Strava-toestemming geweigerd. Er is geen nieuw account gekoppeld.',
      );
    }
    final handoff = uri.queryParameters['handoff'];
    if (handoff == null || handoff.length < 32) {
      throw const IntegrationFailure(
        'OAuth-terugkeer mist een geldige eenmalige overdracht.',
      );
    }
    final token = await _backend('exchange', {
      'state': state,
      'handoff': handoff,
      'code_verifier': verifier,
    });
    if (token['athlete'] is! Map ||
        token['athlete']['id'] is! int ||
        token['scope'] is! String) {
      throw const FormatException('OAuth-antwoord mist account of rechten');
    }
    final old = await store.read('strava-token');
    if (old != null &&
        jsonDecode(old)['athlete']?['id'] != token['athlete']['id']) {
      throw const IntegrationFailure(
        'Ontkoppel eerst het bestaande account voordat je een ander account verbindt.',
      );
    }
    await store.write('strava-token', jsonEncode(token));
    await store.write('strava-reconnect', null);
    await cancelAuthorization();
  }

  Future<void> cancelAuthorization() async {
    for (final key in [
      'strava-state',
      'strava-verifier',
      'strava-auth-started',
    ]) {
      await store.write(key, null);
    }
  }

  Future<Map<String, dynamic>?> account() async {
    final raw = await store.read('strava-token');
    return raw == null ? null : jsonDecode(raw);
  }

  Future<Set<String>> scopes() async =>
      ((await account())?['scope'] as String? ?? '')
          .split(RegExp(r'[, ]+'))
          .where((s) => s.isNotEmpty)
          .toSet();

  Future<String> accessToken({bool force = false}) async {
    final raw = await store.read('strava-token');
    if (raw == null) throw StateError('Strava niet verbonden');
    final token = jsonDecode(raw) as Map<String, dynamic>;
    if (!force &&
        (token['expires_at'] as num) * 1000 >
            now().millisecondsSinceEpoch + 60000) {
      return token['access_token'];
    }
    return _refresh ??= _renew(token).whenComplete(() => _refresh = null);
  }

  Future<String> _renew(Map<String, dynamic> token) async {
    final next = await _backend('refresh', {
      'refresh_token': token['refresh_token'],
      'session': token['session'],
    });
    next['session'] ??= token['session'];
    next['athlete'] ??= token['athlete'];
    next['scope'] ??= token['scope'];
    await store.write('strava-token', jsonEncode(next));
    return next['access_token'];
  }

  Future<void> disconnect() async {
    Object? error;
    try {
      final raw = await account();
      if (raw != null) {
        final token = await accessToken();
        final r = await client
            .post(
              Uri.parse('https://www.strava.com/oauth/deauthorize'),
              headers: {'Authorization': 'Bearer $token'},
            )
            .timeout(const Duration(seconds: 20));
        if (r.statusCode != 200 && r.statusCode != 401) {
          throw const IntegrationFailure(
            'Intrekken bij Strava mislukt. Trek toegang ook in via Strava → My Apps.',
          );
        }
      }
    } catch (e) {
      error = e;
    }
    for (final k in [
      'strava-token',
      'strava-state',
      'strava-verifier',
      'strava-auth-started',
      'strava-reconnect',
    ]) {
      await store.write(k, null);
    }
    if (error != null) {
      throw const IntegrationFailure(
        'Lokaal ontkoppeld. Online intrekken niet bevestigd; controleer Strava → My Apps.',
      );
    }
  }

  Future<http.Response> api(
    String path, {
    Map<String, String>? query,
    bool retry = true,
  }) async {
    await _quotaGuard();
    final token = await accessToken();
    final response = await client
        .get(
          Uri.https('www.strava.com', '/api/v3/$path', query),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 25));
    await _recordQuota(response.headers);
    if (response.statusCode == 401 && retry) {
      await accessToken(force: true);
      return api(path, query: query, retry: false);
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      await store.write('strava-reconnect', 'true');
      throw const IntegrationFailure(
        'Strava-toegang ontbreekt of is ingetrokken. Verbind opnieuw.',
        authentication: true,
      );
    }
    if (response.statusCode == 429) {
      final seconds = int.tryParse(response.headers['retry-after'] ?? '');
      DateTime? date;
      try {
        date = HttpDate.parse(response.headers['retry-after'] ?? '');
      } catch (_) {}
      final delay = seconds != null
          ? Duration(seconds: seconds)
          : date?.difference(now()) ?? const Duration(minutes: 16);
      await database.putDocument(
        'integration-quota',
        'strava',
        now()
            .add(delay.isNegative ? const Duration(minutes: 1) : delay)
            .toUtc()
            .toIso8601String(),
      );
      throw IntegrationFailure(
        'Strava API-limiet bereikt. Later opnieuw proberen.',
        retryAfter: seconds != null
            ? Duration(seconds: seconds)
            : date?.difference(now()) ?? const Duration(minutes: 16),
      );
    }
    if (response.statusCode >= 500) {
      throw const IntegrationFailure(
        'Strava tijdelijk niet bereikbaar.',
        retryAfter: Duration(minutes: 5),
      );
    }
    if (response.statusCode != 200 && response.statusCode != 404) {
      throw IntegrationFailure(
        'Strava-verzoek geweigerd (HTTP ${response.statusCode}).',
      );
    }
    return response;
  }

  Future<void> _quotaGuard() async {
    final next = DateTime.tryParse(
      await database.getDocument('integration-quota', 'strava') ?? '',
    );
    if (next != null && next.isAfter(now())) {
      throw IntegrationFailure(
        'Strava API-limiet: wacht tot de toegestane volgende poging.',
        retryAfter: next.difference(now()),
      );
    }
  }

  Future<void> _recordQuota(Map<String, String> headers) async {
    DateTime? until;
    final current = now().toUtc();
    for (final prefix in ['x-ratelimit', 'x-readratelimit']) {
      final limits = (headers['$prefix-limit'] ?? '')
          .split(',')
          .map((s) => int.tryParse(s.trim()))
          .toList();
      final usage = (headers['$prefix-usage'] ?? '')
          .split(',')
          .map((s) => int.tryParse(s.trim()))
          .toList();
      if (limits.length != 2 ||
          usage.length != 2 ||
          limits.contains(null) ||
          usage.contains(null)) {
        continue;
      }
      if (usage[0]! >= limits[0]!) {
        final boundary = DateTime.utc(
          current.year,
          current.month,
          current.day,
          current.hour,
          (current.minute ~/ 15 + 1) * 15,
        );
        if (until == null || boundary.isAfter(until)) until = boundary;
      }
      if (usage[1]! >= limits[1]!) {
        final boundary = DateTime.utc(
          current.year,
          current.month,
          current.day + 1,
        );
        if (until == null || boundary.isAfter(until)) until = boundary;
      }
    }
    if (until != null) {
      await database.putDocument(
        'integration-quota',
        'strava',
        until.toIso8601String(),
      );
    }
  }

  Future<void> enqueue(String id) async {
    if (id.startsWith('strava:') ||
        await database.getDocument('activity-source', id) != null) {
      throw const IntegrationFailure(
        'Geïmporteerde activiteiten worden niet opnieuw gepubliceerd.',
      );
    }
    await database.transaction(() async {
      if (await database.getDocument('sync', id) != null) return;
      if (await database.getDocument('ride', id) == null) {
        throw StateError('Volledig GPS-spoor ontbreekt');
      }
      await database.putDocument(
        'sync',
        id,
        jsonEncode({'status': 'pending', 'attempts': 0, 'next': 0}),
      );
    });
  }

  Future<void> sync() async {
    if (_syncing) return;
    _syncing = true;
    try {
      for (final entry in (await database.documents('sync')).entries) {
        final job = jsonDecode(entry.value) as Map<String, dynamic>;
        if (['complete', 'unknown', 'failed'].contains(job['status']) ||
            (job['next'] as num? ?? 0) > now().millisecondsSinceEpoch) {
          continue;
        }
        if (job['status'] == 'uploading') {
          job['status'] = 'unknown';
          await _save(entry.key, job);
          continue;
        }
        try {
          await _quotaGuard();
          final token = await accessToken();
          http.Response response;
          if (job['upload_id'] != null) {
            response = await client
                .get(
                  Uri.parse(
                    'https://www.strava.com/api/v3/uploads/${job['upload_id']}',
                  ),
                  headers: {'Authorization': 'Bearer $token'},
                )
                .timeout(const Duration(seconds: 25));
          } else {
            final payload = await database.getDocument('ride', entry.key);
            if (payload == null) {
              job['status'] = 'failed';
              job['error'] = 'Lokale rit verwijderd';
              await _save(entry.key, job);
              continue;
            }
            job['status'] = 'uploading';
            await _save(entry.key, job);
            final request =
                http.MultipartRequest(
                    'POST',
                    Uri.parse('https://www.strava.com/api/v3/uploads'),
                  )
                  ..headers['Authorization'] = 'Bearer $token'
                  ..fields.addAll({
                    'data_type': 'gpx',
                    'sport_type': 'Ride',
                    'external_id': '${entry.key}.gpx',
                  })
                  ..files.add(
                    http.MultipartFile.fromString(
                      'file',
                      GpxExportService.exportToGpx(
                        SessionCodec.decode(payload),
                      ),
                      filename: '${entry.key}.gpx',
                    ),
                  );
            response = await http.Response.fromStream(
              await client.send(request).timeout(const Duration(seconds: 30)),
            );
          }
          await _recordQuota(response.headers);
          if (response.statusCode == 429 || response.statusCode >= 500) {
            // An upload 5xx can mean the server accepted it: do not blindly duplicate it.
            if (job['upload_id'] == null && response.statusCode >= 500) {
              job['status'] = 'unknown';
              job['error'] = 'Controleer Strava vóór opnieuw uploaden';
            } else {
              job['status'] = 'pending';
              job['attempts'] = (job['attempts'] as int) + 1;
              final retrySeconds = int.tryParse(
                response.headers['retry-after'] ?? '',
              );
              job['next'] = now()
                  .add(
                    retrySeconds == null
                        ? Duration(
                            minutes: min(
                              60,
                              1 << min(6, job['attempts'] as int),
                            ),
                          )
                        : Duration(seconds: retrySeconds),
                  )
                  .millisecondsSinceEpoch;
            }
          } else if (response.statusCode == 401) {
            await accessToken(force: true);
            job['status'] = 'pending';
          } else if (response.statusCode != 200 && response.statusCode != 201) {
            job['status'] = 'failed';
            job['error'] = 'HTTP ${response.statusCode}';
          } else {
            final result = jsonDecode(response.body);
            job['upload_id'] = result['id'];
            if (result['error'] != null) {
              job['status'] = 'failed';
              job['error'] = 'Strava heeft het bestand geweigerd; controleer op dubbele activiteit';
            } else if (result['activity_id'] != null) {
              job['status'] = 'complete';
              job['activity_id'] = result['activity_id'];
            } else {
              job['status'] = 'pending';
              job['next'] = now()
                  .add(const Duration(seconds: 15))
                  .millisecondsSinceEpoch;
            }
          }
        } catch (_) {
          job['status'] = job['status'] == 'uploading' ? 'unknown' : 'pending';
          job['error'] = job['status'] == 'unknown'
              ? 'Uploadstatus onzeker: controleer Strava'
              : 'Netwerk of authenticatie niet beschikbaar';
          job['next'] = now()
              .add(const Duration(minutes: 5))
              .millisecondsSinceEpoch;
        }
        await _save(entry.key, job);
      }
    } finally {
      _syncing = false;
    }
  }

  Future<void> _save(String id, Map<String, dynamic> job) =>
      database.putDocument('sync', id, jsonEncode(job));
  void dispose() => client.close();
}
