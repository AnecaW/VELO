import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bike_computer/database/bike_computer_database.dart';
import 'package:bike_computer/services/integrations/strava_service.dart';
import 'package:bike_computer/services/ride/ride_history_service.dart';
import 'package:bike_computer/models/ride_session.dart';
import 'package:bike_computer/services/navigation/routing_client.dart';
import 'package:bike_computer/services/navigation/gpx_route.dart';
import 'package:bike_computer/services/training/interval_engine.dart';

class MemoryTokens implements TokenStore {
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

void main() {
  late BikeComputerDatabase db;
  late MemoryTokens store;
  late DateTime time;
  setUp(() async {
    db = BikeComputerDatabase(executor: NativeDatabase.memory());
    store = MemoryTokens();
    time = DateTime.utc(2026);
    await store.write('strava-base', 'https://oauth.example');
    await store.write(
      'strava-token',
      jsonEncode({
        'access_token': 'old',
        'refresh_token': 'refresh',
        'expires_at':
            time.add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
        'session': 'backend-session',
      }),
    );
  });
  tearDown(() async {
    await db.close();
  });
  test('unexpired access token avoids unnecessary refresh', () async {
    final s = StravaService(
      db,
      store: store,
      now: () => time,
      client: MockClient((_) async => throw StateError('Unexpected network')),
    );
    expect(await s.accessToken(), 'old');
    s.dispose();
  });
  test(
    'token renewal rotates refresh token and serializes concurrent refresh',
    () async {
      time = time.add(const Duration(hours: 2));
      var calls = 0;
      final s = StravaService(
        db,
        store: store,
        now: () => time,
        client: MockClient((request) async {
          calls++;
          expect(jsonDecode(request.body)['refresh_token'], 'refresh');
          return http.Response(
            jsonEncode({
              'access_token': 'new',
              'refresh_token': 'rotated',
              'expires_at':
                  time.add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
                  1000,
            }),
            200,
          );
        }),
      );
      expect(await Future.wait([s.accessToken(), s.accessToken()]), [
        'new',
        'new',
      ]);
      expect(calls, 1);
      expect(
        jsonDecode((await store.read('strava-token'))!)['refresh_token'],
        'rotated',
      );
      s.dispose();
    },
  );
  test('failed refresh preserves existing credentials', () async {
    time = time.add(const Duration(hours: 2));
    final s = StravaService(
      db,
      store: store,
      now: () => time,
      client: MockClient((_) async => http.Response('{}', 503)),
    );
    await expectLater(s.accessToken(), throwsStateError);
    expect(await store.read('strava-token'), contains('refresh'));
    s.dispose();
  });
  test('enqueue is persistent and prevents duplicates', () async {
    await RideHistoryService(database: db)
        .saveRide(const RideSession(id: 'same', state: RideState.finished));
    final s = StravaService(db, store: store);
    await s.enqueue('same');
    await s.enqueue('same');
    expect((await db.documents('sync')).length, 1);
    s.dispose();
  });
  test(
    '429 schedules retry and does not duplicate upload immediately',
    () async {
      await RideHistoryService(database: db)
          .saveRide(const RideSession(id: 'retry', state: RideState.finished));
      var calls = 0;
      final s = StravaService(
        db,
        store: store,
        now: () => time,
        client: MockClient((_) async {
          calls++;
          return http.Response('{}', 429);
        }),
      );
      await s.enqueue('retry');
      await s.sync();
      await s.sync();
      expect(calls, 1);
      final job = jsonDecode((await db.getDocument('sync', 'retry'))!);
      expect(job['status'], 'pending');
      expect(job['next'], greaterThan(time.millisecondsSinceEpoch));
      s.dispose();
    },
  );
  test('ambiguous upload error is never blindly retried', () async {
    await RideHistoryService(database: db)
        .saveRide(const RideSession(id: 'unknown', state: RideState.finished));
    var calls = 0;
    final s = StravaService(
      db,
      store: store,
      now: () => time,
      client: MockClient((_) async {
        calls++;
        throw Exception('Network lost after upload');
      }),
    );
    await s.enqueue('unknown');
    await s.sync();
    time = time.add(const Duration(days: 1));
    await s.sync();
    expect(calls, 1);
    expect(
      jsonDecode((await db.getDocument('sync', 'unknown'))!)['status'],
      'unknown',
    );
    s.dispose();
  });
  test(
    'upload ID is persisted and subsequent sync polls rather than uploading',
    () async {
      await RideHistoryService(database: db)
          .saveRide(const RideSession(id: 'upload', state: RideState.finished));
      final methods = <String>[];
      final s = StravaService(
        db,
        store: store,
        now: () => time,
        client: MockClient((r) async {
          methods.add(r.method);
          return http.Response(
            jsonEncode(
              r.method == 'POST'
                  ? {'id': 123, 'activity_id': null, 'error': null}
                  : {'id': 123, 'activity_id': 456, 'error': null},
            ),
            r.method == 'POST' ? 201 : 200,
          );
        }),
      );
      await s.enqueue('upload');
      await s.sync();
      time = time.add(const Duration(seconds: 20));
      await s.sync();
      await s.sync();
      expect(methods, ['POST', 'GET']);
      expect(
        jsonDecode((await db.getDocument('sync', 'upload'))!)['activity_id'],
        456,
      );
      s.dispose();
    },
  );
  test('routing uses actual returned road geometry and instructions', () async {
    final client = RoutingClient(
      client: MockClient((r) async {
        expect(r.url.path, contains('cycling-road'));
        expect(r.headers['Authorization'], 'key');
        return http.Response(
          jsonEncode({
            'features': [
              {
                'geometry': {
                  'coordinates': [
                    [4, 51, 10],
                    [4.001, 51, 11],
                    [4.001, 51.001, 12],
                  ],
                },
                'properties': {
                  'segments': [
                    {
                      'steps': [
                        {
                          'way_points': [1, 2],
                          'instruction': 'Turn left',
                        },
                      ],
                    },
                  ],
                },
              },
            ],
          }),
          200,
        );
      }),
    );
    final route = await client.route(
      const NavPoint(51, 4),
      const NavPoint(51.001, 4.001),
      'key',
      profile: 'cycling-road',
    );
    expect(route.points.length, 3);
    expect(route.steps.single.instruction, 'Turn left');
    client.dispose();
  });
  test('routing error does not manufacture a straight line route', () async {
    final client = RoutingClient(
      client: MockClient((_) async => http.Response('{}', 503)),
    );
    await expectLater(
      client.route(const NavPoint(51, 4), const NavPoint(51.1, 4.1), 'key'),
      throwsStateError,
    );
    client.dispose();
  });
  test(
    'geocoding presents provider candidates without inventing a location',
    () async {
      final client = RoutingClient(
        client: MockClient((r) async {
          expect(r.url.queryParameters['text'], 'Brussel');
          return http.Response(
            jsonEncode({
              'features': [
                {
                  'properties': {'label': 'Brussel, België'},
                  'geometry': {
                    'coordinates': [4.35, 50.85],
                  },
                },
              ],
            }),
            200,
          );
        }),
      );
      final places = await client.search('Brussel', 'key');
      expect(places.single.point.lat, 50.85);
      expect(places.single.label, 'Brussel, België');
      client.dispose();
    },
  );
  test('FTP zones use explicit percentage boundaries', () {
    expect(IntervalEngine.powerZone(137.5, 250), 1);
    expect(IntervalEngine.powerZone(250, 250), 4);
    expect(IntervalEngine.powerZone(400, 250), 7);
    expect(() => IntervalEngine.powerZone(100, 0), throwsArgumentError);
  });
  test('interval timer advances across steps, pauses and completes', () {
    final e = IntervalEngine(const [
      WorkoutStep('a', 10, .5),
      WorkoutStep('b', 20, 1),
    ]);
    e.advance(12);
    expect(e.index, 1);
    expect(e.remaining, 18);
    e.paused = true;
    e.advance(5);
    expect(e.remaining, 18);
    e.paused = false;
    e.advance(18);
    expect(e.complete, isTrue);
    expect(e.remaining, 0);
  });
  test('interval skip moves to next step without negative remaining time', () {
    final e = IntervalEngine(const [WorkoutStep('a', 10, .5)]);
    e.skip();
    expect(e.complete, isTrue);
    expect(e.remaining, 0);
  });
}
