import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bike_computer/core/runtime.dart';
import 'package:bike_computer/core/settings.dart';
import 'package:bike_computer/database/bike_computer_database.dart';
import 'package:bike_computer/models/bike_type.dart';
import 'package:bike_computer/models/gps_models.dart';
import 'package:bike_computer/models/ride_session.dart';
import 'package:bike_computer/services/gps/gps_service.dart';
import 'package:bike_computer/services/gps/shared_location.dart';
import 'package:bike_computer/services/navigation/geocoding_service.dart';
import 'package:bike_computer/services/navigation/brouter_service.dart';
import 'package:bike_computer/services/navigation/gpx_route.dart';
import 'package:bike_computer/services/navigation/navigation_service.dart';
import 'package:bike_computer/services/ride/session_codec.dart';
import 'package:bike_computer/services/ride/ride_recording_service.dart';
import 'package:bike_computer/features/navigation/navigation_screen.dart';
import 'package:bike_computer/widgets/bike_type_selector.dart';

class GPSFixture implements GPSService {
  final events = StreamController<GPSLocation>.broadcast();
  int starts = 0, stops = 0;
  @override
  Stream<GPSLocation> get locationStream => events.stream;
  @override
  Future<void> startListening() async {
    starts++;
  }

  @override
  Future<void> stopListening() async {
    stops++;
  }

  @override
  Future<bool> isAvailable() async => true;
  @override
  GPSLocation? getLastLocation() => null;
}

GPSLocation fix(double lat, double lon, DateTime time) => GPSLocation(
  latitude: lat,
  longitude: lon,
  altitude: 10,
  accuracy: 5,
  speed: 5,
  heading: 0,
  timestamp: time,
);
Map<String, dynamic> feature(String title) => {
  'geometry': {
    'coordinates': [4.14, 51.16],
  },
  'properties': {
    'name': title,
    'city': 'Sint-Niklaas',
    'postcode': '9100',
    'country': 'België',
  },
};

class SearchFixture implements GeocodingService {
  int calls = 0;
  bool fail = false;
  @override
  Future<List<AddressResult>> search(String q, {NavPoint? focus}) async {
    calls++;
    if (fail) throw StateError('offline');
    return [
      const AddressResult('Grote Markt', 'Sint-Niklaas', NavPoint(51.16, 4.14)),
    ];
  }

  @override
  Future<AddressResult?> reverse(NavPoint p) async =>
      AddressResult('Kaartbestemming', 'Herkenbaar adres', p);
  @override
  void dispose() {}
}

class RouterFixture implements CyclingRouter {
  BikeType? bike;
  @override
  Future<NavRoute> calculate(
    NavPoint start,
    NavPoint end,
    BikeType bike, {
    int alternative = 0,
  }) async {
    this.bike = bike;
    return NavRoute(
      'Providerroute',
      [start, end],
      steps: [const NavStep(1, 'Sla rechtsaf')],
      durationSeconds: 300,
      ascent: 12,
      provider: 'fixture',
      bikeType: bike.name,
    );
  }

  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BikeComputerDatabase db;
  setUp(() async {
    db = BikeComputerDatabase(executor: NativeDatabase.memory());
    Runtime.configure(db);
    await db.putDocument("test", "initialized", "true");
  });
  tearDown(() async {
    await db.close();
  });
  test(
    'eight types map to official sport types and separate cycling profiles',
    () {
      expect(BikeType.values.length, 8);
      expect(BikeType.values.map((b) => b.sportType), [
        'Ride',
        'MountainBikeRide',
        'GravelRide',
        'EBikeRide',
        'EMountainBikeRide',
        'Ride',
        'Ride',
        'Ride',
      ]);
      expect(
        BikeType.road.routingProfile,
        isNot(BikeType.mountain.routingProfile),
      );
      expect(BikeType.gravel.routingProfile, 'gravel');
    },
  );
  test(
    'bike preference survives reload and never changes saved snapshot',
    () async {
      await Runtime.settings.set('bikeType', 'gravel');
      final settings = AppSettings(db);
      await settings.load();
      expect(settings.value('bikeType', ''), 'gravel');
      const ride = RideSession(
        state: RideState.saved,
        bikeType: BikeType.mountain,
      );
      final raw = SessionCodec.encode(ride);
      await Runtime.settings.set('bikeType', 'road');
      expect(SessionCodec.decode(raw).bikeType, BikeType.mountain);
      expect(jsonDecode(raw)['sport_type'], 'MountainBikeRide');
      final legacy = jsonDecode(raw)..remove('bikeType');
      expect(SessionCodec.decode(jsonEncode(legacy)).bikeType, BikeType.road);
    },
  );
  test('shared GPS starts one source, navigation stop does not interrupt recording', () async {
    final source = GPSFixture(), hub = LocationHub(GPSFixture());
    final shared = LocationHub(source),
        nav = shared.lease(),
        ride = shared.lease();
    await Future.wait([nav.startListening(), ride.startListening()]);
    expect(source.starts, 1);
    await nav.stopListening();
    expect(source.stops, 0);
    final received = ride.locationStream.first;
    source.events.add(fix(51, 4, DateTime.now()));
    expect((await received).latitude, 51);
    await ride.stopListening();
    expect(source.stops, 1);
    await source.events.close();
    await hub.source.stopListening();
  });
  test(
    'recording retains bike type through pause resume and recovery codec',
    () async {
      final gps = GPSFixture();
      final recorder = RideRecordingService(gpsService: gps);
      await recorder.initializeRide();
      recorder.setBikeType(BikeType.electricMountain);
      await recorder.startRecording();
      expect(() => recorder.setBikeType(BikeType.road), throwsStateError);
      await recorder.pauseRecording();
      await recorder.startRecording();
      expect(recorder.currentSession.bikeType, BikeType.electricMountain);
      expect(
        SessionCodec.decode(SessionCodec.encode(recorder.currentSession))
            .bikeType,
        BikeType.electricMountain,
      );
      await recorder.stopRecording();
      recorder.dispose();
      await gps.events.close();
    },
  );
  test('Photon formats Belgian addresses, biases location, caches without new network calls', () async {
    int calls = 0;
    final service = PhotonGeocoder(
      db,
      client: MockClient((request) async {
        calls++;
        expect(request.url.queryParameters['q'], 'Grote Mà');
        expect(request.url.queryParameters['lat'], '51.16');
        expect(request.url.queryParameters.containsKey('lang'), false);
        return http.Response(
          jsonEncode({
            'features': [feature('Grote Markt')],
          }),
          200,
        );
      }),
    );
    final result = await service.search(
      'Grote Mà',
      focus: const NavPoint(51.16, 4.14),
    );
    expect(result.single.label, contains('België'));
    expect(result.single.subtitle, contains('9100'));
    expect(
      (await service.search(
        'Grote Mà',
        focus: const NavPoint(51.16, 4.14),
      )).length,
      1,
    );
    expect(calls, 1);
    expect(service.cached, true);
    service.dispose();
  });
  test(
    'Photon minimum query length and Dutch postcode results; reverse endpoint',
    () async {
      int calls = 0;
      final service = PhotonGeocoder(
        db,
        client: MockClient((r) async {
          calls++;
          if (calls == 1) {
            expect(r.url.queryParameters['q'], '1012');
          } else {
            expect(r.url.path, '/reverse');
          }
          return http.Response(
            jsonEncode({
              'features': [
                {
                  'geometry': {
                    'coordinates': [4.9, 52.37],
                  },
                  'properties': {
                    'street': 'Damrak',
                    'housenumber': '1',
                    'city': 'Amsterdam',
                    'postcode': '1012',
                    'country': 'Nederland',
                  },
                },
              ],
            }),
            200,
          );
        }),
      );
      expect(await service.search('ab'), isEmpty);
      final result = await service.search('1012');
      expect(result.single.title, 'Damrak 1');
      expect(result.single.label, contains('Amsterdam'));
      expect(
        (await service.reverse(const NavPoint(52.37, 4.9)))!.label,
        contains('Nederland'),
      );
      service.dispose();
    },
  );
  test('provider errors are explicit and do not create fake results', () async {
    final search = PhotonGeocoder(
      db,
      client: MockClient((_) async => http.Response('limit', 429)),
    );
    await expectLater(search.search('Antwerpen'), throwsStateError);
    search.dispose();
    final router = BRouterService(
      client: MockClient((_) async => http.Response('unavailable', 503)),
    );
    await expectLater(
      router.calculate(
        const NavPoint(51, 4),
        const NavPoint(51.01, 4.01),
        BikeType.road,
      ),
      throwsStateError,
    );
    router.dispose();
  });
  test('BRouter uses sport-specific profile, real geometry, supplied times, elevation and hints', () async {
    final router = BRouterService(
      client: MockClient((r) async {
        expect(r.url.queryParameters['profile'], 'mtb');
        expect(r.url.queryParameters['timode'], '1');
        expect(r.url.queryParameters['alternativeidx'], '1');
        return http.Response(
          jsonEncode({
            'features': [
              {
                'geometry': {
                  'coordinates': [
                    [4, 51, 10],
                    [4.01, 51.01, 12],
                  ],
                },
                'properties': {
                  'total-time': '120',
                  'filtered ascend': '2',
                  'voicehints': [
                    [1, 5, 0, 12, 90],
                  ],
                },
              },
            ],
          }),
          200,
        );
      }),
    );
    final route = await router.calculate(
      const NavPoint(51, 4),
      const NavPoint(51.01, 4.01),
      BikeType.mountain,
      alternative: 1,
    );
    expect(route.steps.single.instruction, 'Sla rechtsaf');
    expect(route.durationSeconds, 120);
    expect(route.ascent, 2);
    expect(route.points.last.elevation, 12);
    final stored = NavRoute.decode(route.encode());
    expect(stored.bikeType, 'mountain');
    expect(stored.provider, 'BRouter');
    expect(stored.durationSeconds, 120);
    router.dispose();
  });
  test(
    'missing provider measurements remain absent, unknown turns omitted',
    () {
      final route = BRouterService.parse(
        {
          'features': [
            {
              'geometry': {
                'coordinates': [
                  [4, 51],
                  [4.01, 51.01],
                ],
              },
              'properties': {
                'voicehints': [
                  [1, 999, 0, 5, 0],
                ],
              },
            },
          ],
        },
        BikeType.city,
        0,
      );
      expect(route.durationSeconds, isNull);
      expect(route.ascent, isNull);
      expect(route.steps, isEmpty);
    },
  );
  test('off-route detection ignores jitter, requires dwell and backs off', () {
    final detector = OffRouteDetector(), start = DateTime.utc(2026);
    const off = RouteProgress(0, 1000, 100, 1, true),
        on = RouteProgress(0, 1000, 1, 1, false);
    expect(detector.shouldRecalculate(off, 5, start), false);
    expect(
      detector.shouldRecalculate(on, 5, start.add(const Duration(seconds: 10))),
      false,
    );
    expect(
      detector.shouldRecalculate(
        off,
        5,
        start.add(const Duration(seconds: 20)),
      ),
      false,
    );
    expect(
      detector.shouldRecalculate(
        off,
        50,
        start.add(const Duration(seconds: 40)),
      ),
      false,
    );
    expect(
      detector.shouldRecalculate(
        off,
        5,
        start.add(const Duration(seconds: 41)),
      ),
      false,
    );
    expect(
      detector.shouldRecalculate(
        off,
        5,
        start.add(const Duration(seconds: 54)),
      ),
      true,
    );
    expect(
      detector.shouldRecalculate(
        off,
        5,
        start.add(const Duration(seconds: 70)),
      ),
      false,
    );
    expect(
      detector.shouldRecalculate(
        off,
        5,
        start.add(const Duration(seconds: 115)),
      ),
      true,
    );
  });
  test(
    'a recording keeps real input points while a navigation lease stops',
    () async {
      final source = GPSFixture(), shared = LocationHub(GPSFixture());
      final hub = LocationHub(source), nav = hub.lease();
      final recorder = RideRecordingService(gpsService: hub.lease());
      await nav.startListening();
      await recorder.initializeRide();
      recorder.setBikeType(BikeType.gravel);
      await recorder.startRecording();
      final t = DateTime.now();
      source.events.add(fix(51, 4, t));
      await Future<void>.delayed(Duration.zero);
      source.events.add(fix(51.00005, 4, t.add(const Duration(seconds: 2))));
      await Future<void>.delayed(Duration.zero);
      await nav.stopListening();
      expect(source.stops, 0);
      source.events.add(fix(51.0001, 4, t.add(const Duration(seconds: 4))));
      await Future<void>.delayed(Duration.zero);
      expect(recorder.currentSession.trackPoints.length, 3);
      expect(recorder.currentSession.totalDistance, greaterThan(0));
      expect(recorder.currentSession.bikeType, BikeType.gravel);
      await recorder.stopRecording();
      expect(source.stops, 1);
      recorder.dispose();
      await source.events.close();
      await shared.source.stopListening();
    },
  );
  test('Google Maps URL carries destination and bicycle mode only on explicit invocation', () {
    final url = ExternalNavigation.googleMaps(const NavPoint(51, 4));
    expect(url.scheme, 'https');
    expect(url.queryParameters['travelmode'], 'bicycling');
    expect(url.queryParameters['destination'], '51.0,4.0');
  });
  testWidgets(
    'bike selector chooses road, mountain, gravel in two taps and remembers choice',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: BikeTypeSelector())),
      );
      for (final bike in [BikeType.mountain, BikeType.gravel, BikeType.road]) {
        await tester.tap(find.byType(PopupMenuButton<BikeType>));
        await tester.pumpAndSettle();
        await tester.tap(find.text(bike.label).last);
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await tester.pumpAndSettle();
        expect(Runtime.settings.value('bikeType', ''), bike.name);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'autocomplete debounces, selects destination, calculates by bike and navigates',
    (tester) async {
      final gps = GPSFixture(),
          search = SearchFixture(),
          router = RouterFixture();
      await tester.runAsync(() => Runtime.settings.set('bikeType', 'gravel'));
      await tester.pumpWidget(
        MaterialApp(
          home: NavigationScreen(
            geocoder: search,
            router: router,
            gps: gps,
            platformServices: false,
            locate: () async => fix(51.15, 4.13, DateTime.now()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 250);
      addTearDown(tester.view.resetViewInsets);
      await tester.enterText(find.byType(TextField), 'Gro');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField), 'Grote Markt');
      await tester.pump(const Duration(milliseconds: 599));
      expect(search.calls, 0);
      await tester.pump(const Duration(milliseconds: 2));
      await tester.pumpAndSettle();
      expect(search.calls, 1);
      expect(find.byType(BikeTypeSelector), findsNothing);
      await tester.tap(find.text('Grote Markt').last);
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(find.text('Bereken route'), findsOneWidget);
      await tester.tap(find.text('Bereken route'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(router.bike, BikeType.gravel);
      expect(find.text('Navigeren in VELO'), findsOneWidget);
      await tester.tap(find.text('Navigeren in VELO'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
      gps.events.add(fix(51.155, 4.135, DateTime.now()));
      await tester.pumpAndSettle();
      expect(find.text('Stop navigatie'), findsOneWidget);
      expect(find.text('Sla rechtsaf'), findsOneWidget);
      await tester.tap(find.text('Stop navigatie'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Navigeren in VELO'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await gps.events.close();
    },
  );
}
