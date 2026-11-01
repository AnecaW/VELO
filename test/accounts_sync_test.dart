import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bike_computer/database/bike_computer_database.dart';
import 'package:bike_computer/core/runtime.dart';
import 'package:bike_computer/features/integrations/connected_apps_screen.dart';
import 'package:bike_computer/services/integrations/integration_models.dart';
import 'package:bike_computer/services/integrations/strava_service.dart';
import 'package:bike_computer/services/integrations/strava_integration.dart';
import 'package:bike_computer/services/integrations/sync_engine.dart';
import 'package:bike_computer/services/integrations/sync_scheduler.dart';
import 'package:bike_computer/services/storage/backup_service.dart';
import 'package:bike_computer/services/integrations/gpx_exchange_service.dart';

class Tokens implements TokenStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}

class Provider implements IntegrationProvider {
  @override
  String get id => 'strava';
  int calls = 0;
  bool authorized = true;
  Object? failure;
  Completer<void>? wait;
  @override
  Future<bool> connected() async => authorized;
  @override
  Future<void> synchronize(SyncPreferences p, {bool reset = false}) async {
    calls++;
    if (wait != null) await wait!.future;
    if (failure != null) throw failure!;
  }

  @override
  Future<void> disconnect() async {
    authorized = false;
  }
}

void main() {
  late BikeComputerDatabase db;
  late Tokens tokens;
  late DateTime time;
  Map<String, dynamic> token() => {
    'access_token': 'test-access',
    'refresh_token': 'test-refresh',
    'expires_at':
        time.add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
    'athlete': {'id': 7, 'firstname': 'Test'},
    'scope': 'activity:read,read,activity:write',
    'session': 'test-session',
  };
  Map<String, dynamic> activity(int id) => {
    'id': id,
    'name': 'Test-only ride',
    'start_date': '2026-11-01T10:00:00Z',
    'distance': 12000,
    'moving_time': 1200,
    'elapsed_time': 1300,
    'sport_type': 'Ride',
  };
  StravaService service(Future<http.Response> Function(http.Request) fn) =>
      StravaService(
        db,
        store: tokens,
        now: () => time,
        client: MockClient(fn),
        openUrl: (_) async => true,
      );
  setUp(() async {
    db = BikeComputerDatabase(executor: NativeDatabase.memory());
    tokens = Tokens();
    time = DateTime.utc(2026, 11, 1, 12);
    await tokens.write('strava-token', jsonEncode(token()));
    await tokens.write('strava-base', 'https://oauth.example');
  });
  tearDown(() async {
    await db.close();
  });
  test('missing backend configuration never starts OAuth', () async {
    final s = service((_) async => throw StateError('No network expected'));
    await expectLater(s.authorize('', '123'), throwsArgumentError);
    s.dispose();
  });
  test(
    'OAuth launch points to official Strava and saves S256 verifier separately',
    () async {
      await tokens.write('strava-token', null);
      final s = service((r) async {
        final body = jsonDecode(r.body);
        expect(body['code_challenge'].length, 43);
        expect(body.containsKey('client_secret'), false);
        return http.Response(
          jsonEncode({
            'authorization_url': Uri.https(
              'www.strava.com',
              '/oauth/authorize',
              {'state': body['state'], 'client_id': '123'},
            ).toString(),
          }),
          200,
        );
      });
      await s.authorize('https://oauth.example', '123');
      expect(tokens.values['strava-state'], isNotNull);
      expect(
        tokens.values['strava-verifier']!.length,
        greaterThanOrEqualTo(43),
      );
      s.dispose();
    },
  );
  Future<void> pending() async {
    await tokens.write('strava-state', 'state-test');
    await tokens.write('strava-verifier', 'verifier');
    await tokens.write('strava-auth-started', time.toIso8601String());
  }

  test('forged callback state is rejected without token exchange', () async {
    await pending();
    final s = service((_) async => throw StateError('Unexpected exchange'));
    await expectLater(
      s.handleCallback(
        Uri.parse(
          'ultimatebike://oauth/strava?state=forged&handoff=${'a' * 43}',
        ),
      ),
      throwsA(isA<IntegrationFailure>()),
    );
    expect((await s.account())!['access_token'], 'test-access');
    s.dispose();
  });
  test('callback rejects duplicate parameters and wrong host', () async {
    await pending();
    final s = service((_) async => throw StateError('Unexpected exchange'));
    for (final url in [
      'ultimatebike://other/strava?state=state-test',
      'ultimatebike://oauth/strava?state=state-test&state=state-test',
    ]) {
      await expectLater(
        s.handleCallback(Uri.parse(url)),
        throwsA(isA<IntegrationFailure>()),
      );
    }
    s.dispose();
  });
  test('expired authorization cannot exchange', () async {
    await pending();
    time = time.add(const Duration(minutes: 11));
    final s = service((_) async => throw StateError('Unexpected exchange'));
    await expectLater(
      s.handleCallback(
        Uri.parse(
          'ultimatebike://oauth/strava?state=state-test&handoff=${'a' * 43}',
        ),
      ),
      throwsA(isA<IntegrationFailure>()),
    );
    s.dispose();
  });
  test('denied consent clears pending handoff and does not connect', () async {
    await tokens.write('strava-token', null);
    await pending();
    final s = service((_) async => throw StateError('No exchange'));
    await expectLater(
      s.handleCallback(
        Uri.parse(
          'ultimatebike://oauth/strava?state=state-test&error=access_denied',
        ),
      ),
      throwsA(isA<IntegrationFailure>()),
    );
    expect(await s.account(), isNull);
    expect(tokens.values['strava-state'], isNull);
    s.dispose();
  });
  test(
    'successful verified handoff stores exact granted scopes and is single use',
    () async {
      await tokens.write('strava-token', null);
      await pending();
      final s = service((r) async {
        expect(jsonDecode(r.body)['code_verifier'], 'verifier');
        return http.Response(jsonEncode(token()), 200);
      });
      final callback = Uri.parse(
        'ultimatebike://oauth/strava?state=state-test&handoff=${'a' * 43}',
      );
      await s.handleCallback(callback);
      expect((await s.account())!['athlete']['id'], 7);
      expect(await s.scopes(), contains('activity:read'));
      expect(tokens.values['strava-verifier'], isNull);
      await expectLater(
        s.handleCallback(callback),
        throwsA(isA<IntegrationFailure>()),
      );
      s.dispose();
    },
  );
  test('401 refreshes once and never loops indefinitely', () async {
    var requests = 0;
    final s = service((r) async {
      if (r.url.path == '/refresh') {
        return http.Response(jsonEncode(token()), 200);
      }
      requests++;
      return http.Response('{}', 401);
    });
    await expectLater(s.api('athlete'), throwsA(isA<IntegrationFailure>()));
    expect(requests, 2);
    expect(tokens.values['strava-reconnect'], 'true');
    s.dispose();
  });
  test('API Retry-After is exposed without leaking tokens', () async {
    final s = service(
      (_) async => http.Response('{}', 429, headers: {'retry-after': '7200'}),
    );
    try {
      await s.api('athlete');
      fail('Expected rate limit');
    } on IntegrationFailure catch (e) {
      expect(e.retryAfter, const Duration(hours: 2));
      expect(e.toString(), isNot(contains('test-access')));
    }
    s.dispose();
  });
  test(
    'activity import is idempotent and never enters local statistics',
    () async {
      final cache = StravaCache(db, now: () => time);
      await cache.activity(activity(1), 7);
      await cache.activity(activity(1), 7);
      expect((await db.documents('strava-activities')).length, 1);
      expect(await db.getAllRides(), isEmpty);
    },
  );
  test(
    'incomplete activity rejected without guessed distance or time',
    () async {
      final cache = StravaCache(db);
      final raw = activity(1)..remove('distance');
      await expectLater(cache.activity(raw, 7), throwsFormatException);
      expect(await db.documents('strava-activities'), isEmpty);
    },
  );
  test('uploaded local ride does not reappear as imported duplicate', () async {
    await db.putDocument(
      'sync',
      'own',
      jsonEncode({'activity_id': 1, 'status': 'complete'}),
    );
    await StravaCache(db).activity(activity(1), 7);
    expect(await db.documents('strava-activities'), isEmpty);
  });
  const gpx =
      '<gpx version="1.1"><trk><name>Test-only route</name><trkseg><trkpt lat="51" lon="4"/><trkpt lat="51.1" lon="4.1"/></trkseg></trk></gpx>';
  test(
    'routes deduplicate preserve original and are excluded from backup',
    () async {
      final c = StravaCache(db, now: () => time);
      await c.route('1', gpx, 7);
      await c.route('1', gpx, 7);
      expect((await db.documents('routes')).length, 1);
      expect((await db.documents('strava-route-original')).values.single, gpx);
      final backup = jsonDecode(await BackupService(db).export());
      expect(backup['routes'], isEmpty);
    },
  );
  test(
    'expired cache removes activities original route and navigation copy',
    () async {
      final c = StravaCache(db, now: () => time);
      await c.route('1', gpx, 7);
      await c.activity(activity(1), 7);
      await db.putDocument(
        'navigation',
        'selected',
        (await db.documents('routes')).values.single,
      );
      await db.putDocument('navigation', 'source', 'strava:7:1');
      time = time.add(const Duration(hours: 25));
      await c.expire();
      expect(await db.documents('strava-activities'), isEmpty);
      expect(await db.documents('routes'), isEmpty);
      expect(await db.getDocument('navigation', 'selected'), isNull);
      expect(await db.documents('strava-route-original'), isEmpty);
    },
  );
  test('imported activity cannot be sent back to Strava', () async {
    final s = service((_) async => throw StateError('Unexpected network'));
    await expectLater(
      s.enqueue('strava:7:1'),
      throwsA(isA<IntegrationFailure>()),
    );
    s.dispose();
  });
  test('partial pagination never advances cursor', () async {
    var calls = 0;
    final s = service((_) async {
      calls++;
      return calls == 1
          ? http.Response(
              jsonEncode(List.generate(50, (i) => activity(i + 1))),
              200,
            )
          : http.Response('{}', 503);
    });
    final p = StravaIntegration(s);
    await expectLater(
      p.synchronize(const SyncPreferences()),
      throwsA(isA<IntegrationFailure>()),
    );
    expect((await p.repository.state('strava'))['cursor'], isNull);
    expect((await db.documents('strava-activities')).length, 50);
    s.dispose();
  });
  test('incremental sync uses saved cursor with overlap', () async {
    final s = service((r) async {
      expect(
        int.parse(r.url.queryParameters['after']!),
        time.subtract(const Duration(minutes: 10)).millisecondsSinceEpoch ~/
            1000,
      );
      return http.Response('[]', 200);
    });
    final p = StravaIntegration(s);
    await p.repository.update('strava', {
      'cursor': time.subtract(const Duration(minutes: 5)).toIso8601String(),
      'fullRefresh': time.toIso8601String(),
    });
    await p.synchronize(const SyncPreferences());
    expect(
      (await p.repository.state('strava'))['cursor'],
      time.toIso8601String(),
    );
    s.dispose();
  });
  test(
    'disconnect deletes tokens caches and queue even when revoke offline',
    () async {
      final s = service((_) async => throw const IntegrationFailure('Offline'));
      final p = StravaIntegration(s);
      await p.cache.activity(activity(1), 7);
      await db.putDocument('sync', 'local', '{}');
      await expectLater(p.disconnect(), throwsA(isA<IntegrationFailure>()));
      expect(await s.account(), isNull);
      expect(await db.documents('strava-activities'), isEmpty);
      expect(await db.documents('sync'), isEmpty);
      expect((await p.repository.preferences('strava')).enabled, false);
      s.dispose();
    },
  );
  test('automatic triggers require granular consent', () {
    const off = SyncPreferences();
    expect(SyncEngine.permitted(off, 'open'), false);
    expect(SyncEngine.permitted(off, 'manual'), true);
    expect(
      SyncEngine.permitted(const SyncPreferences(enabled: false), 'manual'),
      false,
    );
    expect(
      SyncEngine.permitted(
        const SyncPreferences(automatic: true, onNetwork: false),
        'network',
      ),
      false,
    );
    expect(
      SyncEngine.permitted(
        const SyncPreferences(automatic: true, afterRide: true),
        'ride',
      ),
      true,
    );
  });
  test(
    'offline queued job retries after recovery without duplicate work',
    () async {
      var online = false;
      final p = Provider(), repo = SyncRepository(db);
      final e = SyncEngine(
        p,
        repo,
        network: () async => NetworkState(online, true),
        now: () => time,
      );
      expect(await e.run(), false);
      expect(p.calls, 0);
      online = true;
      expect(await e.run(), false);
      time = time.add(const Duration(minutes: 2));
      expect(await e.run(), true);
      expect(p.calls, 1);
      expect((await repo.state('strava'))['lastSuccess'], isNotNull);
      e.dispose();
    },
  );
  test('wifi-only policy blocks requests on mobile network', () async {
    final p = Provider(), repo = SyncRepository(db);
    await repo.savePreferences('strava', const SyncPreferences(wifiOnly: true));
    final e = SyncEngine(
      p,
      repo,
      network: () async => const NetworkState(true, false),
    );
    expect(await e.run(), false);
    expect(p.calls, 0);
    e.dispose();
  });
  test('database lease prevents overlapping engines', () async {
    final p = Provider()..wait = Completer<void>(), repo = SyncRepository(db);
    final a = SyncEngine(
          p,
          repo,
          network: () async => const NetworkState(true, true),
        ),
        b = SyncEngine(
          p,
          repo,
          network: () async => const NetworkState(true, true),
        );
    final run = a.run();
    while (p.calls == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    await b.run();
    expect(p.calls, 1);
    p.wait!.complete();
    await run;
    a.dispose();
    b.dispose();
  });
  testWidgets('UI shows real disconnected and configured account statuses', (
    tester,
  ) async {
    Runtime.configure(db);
    await tokens.write('strava-token', null);
    final s = service((_) async => http.Response('{}', 200)),
        coordinator = IntegrationCoordinator(StravaIntegration(s));
    await tester.pumpWidget(
      MaterialApp(home: StravaAccountScreen(coordinator: coordinator)),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(find.text('Niet verbonden'), findsOneWidget);
    expect(find.text('Publiek Strava client-ID'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    coordinator.dispose();
  });
  test('serverless GPX import deduplicates content and preserves original source', () async {
    const raw =
        '<gpx version="1.1"><trk><name>Test GPX only</name><trkseg><trkpt lat="51" lon="4"/><trkpt lat="51.1" lon="4.1"/></trkseg></trk></gpx>';
    final s = GpxExchangeService(db),
        a = await GpxExchangeService(db).importRoute(raw, filename: 'test.gpx');
    expect(await s.importRoute(raw), a);
    expect((await db.documents('routes')).length, 1);
    expect(await db.getDocument('gpx-original', a), raw);
    expect(
      jsonDecode((await db.getDocument('route-source', a))!)['source'],
      'GPX-import',
    );
  });
  test('serverless export never manufactures an absent GPS ride', () async {
    await expectLater(
      GpxExchangeService(db).exportRide('missing'),
      throwsFormatException,
    );
    await expectLater(
      GpxExchangeService(db).exportRide('strava:7:1'),
      throwsFormatException,
    );
  });
  for (final status in ['Verbonden', 'Synchronisatie mislukt']) {
    testWidgets('UI displays persisted real state: $status', (tester) async {
      Runtime.configure(db);
      final s = service((_) async => http.Response('[]', 200));
      final coordinator = IntegrationCoordinator(StravaIntegration(s));
      await SyncRepository(db).update('strava', {
        'status': status,
        if (status != 'Verbonden') 'error': 'Offline; probeer later',
      });
      await tester.pumpWidget(
        MaterialApp(home: StravaAccountScreen(coordinator: coordinator)),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      expect(find.text(status), findsOneWidget);
      expect(find.textContaining('account 7'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      coordinator.dispose();
    });
  }
}
