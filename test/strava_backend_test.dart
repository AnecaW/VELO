import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bike_computer/database/bike_computer_database.dart';
import 'package:bike_computer/core/runtime.dart';
import 'package:bike_computer/services/accounts/account_service.dart';
import 'package:bike_computer/services/integrations/backend_strava.dart';
import 'package:bike_computer/services/integrations/strava_integration.dart';
import 'package:bike_computer/services/integrations/sync_scheduler.dart';
import 'package:bike_computer/services/integrations/strava_activity.dart';
import 'package:bike_computer/features/integrations/connected_apps_screen.dart';

import 'accounts_sync_test.dart' show Tokens;

class StravaAccounts extends AccountService {
  StravaAccounts() : super(store: Tokens()) {
    user = {'id': 'alice'};
  }
  bool online = true, configured = true, connected = false;
  int reads = 0, uploads = 0;
  Completer<void>? wait;
  List<Map<String, dynamic>> routes = [];
  Map<String, dynamic>? authorization;
  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    bool authenticated = true,
  }) async {
    if (!online) throw AccountFailure('Geen verbinding met VELO.');
    if (path.endsWith('/authorize')) {
      authorization = Map<String, dynamic>.from(body as Map);
      return {
        'authorization_url': Uri.https(
          'www.strava.com',
          '/oauth/mobile/authorize',
          {'state': authorization!['state'], 'client_id': 'fixture-public-id'},
        ).toString(),
      };
    }
    if (path == '/api/v1/integrations/strava') {
      reads++;
      await wait?.future;
      return {
        'configured': configured,
        'connected': connected,
        'status': connected ? 'connected' : 'disconnected',
        'athlete': {
          'id': user!['id'] == 'alice' ? 42 : 43,
          'firstname': 'Fixture',
        },
        'scope': 'read,activity:read',
        'features': {'activities': true, 'uploads': false, 'routes': true},
        'jobs': [],
        'history': [],
      };
    }
    if (path.contains('/activities?page=')) {
      return {'items': [], 'next_page': null};
    }
    if (path.endsWith('/routes')) return routes;
    if (path.contains('/uploads/')) {
      uploads++;
      return {'job_id': 'fixture-job'};
    }
    return {'revision': 1};
  }
}

class DeferredDetails extends StravaIntegration {
  DeferredDetails(super.service);
  final response = Completer<Map<String, dynamic>>();
  @override
  Future<Map<String, dynamic>> details(int id) => response.future;
}

const track =
    '{"v":1,"id":"ride","points":[[51,4,10,"2026-11-01T10:00:00Z"],[51.01,4.01,11,"2026-11-01T10:01:00Z"]]}';
void main() {
  late BikeComputerDatabase db;
  late StravaAccounts accounts;
  late BackendStravaService service;
  setUp(() async {
    db = BikeComputerDatabase(executor: NativeDatabase.memory());
    accounts = StravaAccounts();
    service = BackendStravaService(db, accounts);
    await db.putDocument('account-owner', 'current', 'alice');
  });
  tearDown(() async {
    service.dispose();
    accounts.dispose();
    await db.close();
  });
  test('official mobile OAuth uses state and a secure verifier, never client secrets', () async {
    Uri? opened;
    final mobile = BackendStravaService(
      db,
      accounts,
      openUrl: (uri) async {
        opened = uri;
        return true;
      },
    );
    await mobile.authorize(
      '',
      '',
      scopes: ['read', 'activity:read', 'activity:write'],
    );
    expect(opened!.host, 'www.strava.com');
    expect(opened!.path, '/oauth/mobile/authorize');
    expect(opened!.queryParameters['state'], accounts.authorization!['state']);
    expect(accounts.authorization!['code_challenge'].length, 43);
    expect(accounts.authorization!.containsKey('client_secret'), isFalse);
    expect(
      (await accounts.store.read('strava-verifier'))!.length,
      greaterThanOrEqualTo(43),
    );
    mobile.dispose();
  });
  test('status requests join in flight and cached profiles are scoped to VELO identity', () async {
    accounts.wait = Completer<void>();
    final first = service.information(), second = service.information();
    await Future<void>.delayed(Duration.zero);
    expect(accounts.reads, 1);
    accounts.wait!.complete();
    final result = await Future.wait([first, second]);
    expect(result.first['athlete']['id'], 42);
    accounts.wait = null;
    accounts.user = {'id': 'bob'};
    expect((await service.information())['athlete']['id'], 43);
    expect(accounts.reads, 2);
  });
  test('manual offline upload survives and resumes even when automatic upload is off', () async {
    await db.putDocument('ride', 'ride', track);
    accounts.online = false;
    await expectLater(service.enqueue('ride'), throwsA(isA<AccountFailure>()));
    expect((await db.documents('strava-upload-outbox')).length, 1);
    accounts.online = true;
    accounts.connected = true;
    await service.flushOutbox();
    expect(accounts.uploads, 1);
    expect(await db.documents('strava-upload-outbox'), isEmpty);
    await service.flushOutbox();
    expect(accounts.uploads, 1);
  });
  test('missing GPS is rejected before a cloud upload can be queued', () async {
    await db.putDocument('ride', 'empty', '{"v":1,"id":"empty","points":[]}');
    await expectLater(service.enqueue('empty'), throwsA(isA<AccountFailure>()));
    expect(accounts.uploads, 0);
    expect(await db.documents('strava-upload-outbox'), isEmpty);
  });
  test('cache hydration preserves active Strava navigation and original server expiry', () async {
    const gpx =
        '<gpx><trk><name>Fixture</name><trkseg><trkpt lat="51" lon="4"/><trkpt lat="51.01" lon="4.01"/></trkseg></trk></gpx>';
    final cache = StravaCache(db);
    await cache.route('7', gpx, 42);
    final route = await db.getDocument('routes', 'strava:42:7');
    await db.putDocument('navigation', 'selected', route!);
    await db.putDocument('navigation', 'source', 'strava:42:7');
    final expiry =
        DateTime.now()
            .toUtc()
            .add(const Duration(hours: 1))
            .millisecondsSinceEpoch ~/
        1000;
    accounts.connected = true;
    accounts.routes = [
      {
        'data': {'id': 7, 'gpx': gpx},
        'expires_at': expiry,
      },
    ];
    await BackendStravaIntegration(service).loadCached();
    expect(await db.getDocument('navigation', 'selected'), route);
    final source = jsonDecode(
      (await db.getDocument('route-source', 'strava:42:7'))!,
    );
    expect(
      DateTime.parse(source['expires']).millisecondsSinceEpoch ~/ 1000,
      expiry,
    );
  });
  testWidgets(
    'missing configuration is explicit and does not show a fake connect action',
    (tester) async {
      Runtime.configure(db);
      accounts.configured = false;
      final coordinator = IntegrationCoordinator(
        BackendStravaIntegration(service),
      );
      await tester.pumpWidget(
        MaterialApp(home: StravaAccountScreen(coordinator: coordinator)),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      expect(find.text('Configuratie ontbreekt'), findsOneWidget);
      expect(find.byKey(const ValueKey('connect-strava')), findsNothing);
      expect(find.textContaining('momenteel niet beschikbaar'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      coordinator.engine.dispose();
    },
  );
  test(
    'Strava map polyline and durations use supplied coordinates and seconds',
    () {
      final points = stravaPolyline(r'_p~iF~ps|U_ulLnnqC_mqNvxq`@');
      expect(points.length, 3);
      expect(points.first.lat, 38.5);
      expect(points.first.lon, -120.2);
      expect(stravaDuration(3661), '1:01:01');
      expect(() => stravaPolyline('?'), throwsFormatException);
    },
  );
  testWidgets(
    'activity details survive inserting the loading indicator above the tapped row',
    (tester) async {
      Runtime.configure(db);
      final data = <String, dynamic>{
        'id': 99,
        'name': 'Fixture activity',
        'distance': 1000,
        'moving_time': 100,
        'elapsed_time': 120,
        'start_date': '2026-11-01T10:00:00Z',
        'average_speed': 10.0,
      };
      final provider = DeferredDetails(service);
      await provider.cache.activity(data, 42);
      await tester.pumpWidget(
        MaterialApp(home: StravaDataScreen(integration: provider)),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      await tester.tap(find.text('Fixture activity'));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      provider.response.complete(data);
      await tester.pumpAndSettle();
      expect(find.text('View on Strava'), findsOneWidget);
      expect(find.text('Gemiddelde snelheid: 36.0 km/h'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
