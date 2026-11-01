import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bike_computer/database/bike_computer_database.dart';
import 'package:bike_computer/features/history/history_screen.dart';
import 'package:bike_computer/models/ride_session.dart';
import 'package:bike_computer/models/gps_models.dart';
import 'package:bike_computer/services/ride/ride_history_service.dart';
import 'package:bike_computer/services/ride/session_codec.dart';
import 'package:bike_computer/core/settings.dart';

void main() {
  test(
    'full track and moving time survive closing and reopening SQLite',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bike-persistence-test',
      );
      final file = File('${dir.path}/test.sqlite');
      var db = BikeComputerDatabase(executor: NativeDatabase(file));
      final ride = RideSession(
        id: 'persistent',
        state: RideState.finished,
        startTime: DateTime.utc(2026),
        totalDistance: 1,
        movingTime: const Duration(minutes: 2),
        pausedTime: const Duration(seconds: 5),
        trackPoints: [
          TrackPoint(
            latitude: 51,
            longitude: 4,
            altitude: 12,
            timestamp: DateTime.utc(2026),
            accuracy: 4,
            heading: 40,
            segmentStart: true,
          ),
        ],
      );
      await RideHistoryService(database: db).saveRide(ride);
      await db.close();
      db = BikeComputerDatabase(executor: NativeDatabase(file));
      final history = RideHistoryService(database: db);
      await history.loadPersistedRides();
      expect(history.getAllRides().single.trackPoints, ride.trackPoints);
      expect(history.getAllRides().single.movingTime, ride.movingTime);
      await db.close();
      await dir.delete(recursive: true);
    },
  );
  test('saving the same ride twice is idempotent', () async {
    final db = BikeComputerDatabase(executor: NativeDatabase.memory());
    final history = RideHistoryService(database: db);
    const ride = RideSession(
      id: 'same',
      state: RideState.finished,
      totalDistance: 2,
    );
    await history.saveRide(ride);
    await history.saveRide(ride);
    expect((await db.getAllRides()).length, 1);
    await db.close();
  });
  test('checkpoint, settings and route survive a new connection', () async {
    final dir = await Directory.systemTemp.createTemp('bike-recovery-test');
    final file = File('${dir.path}/test.sqlite');
    var db = BikeComputerDatabase(executor: NativeDatabase(file));
    await db.putDocument(
      'active',
      'ride',
      SessionCodec.encode(
        const RideSession(state: RideState.recording, totalDistance: 3),
      ),
    );
    await db.putDocument('routes', 'route', 'local');
    await AppSettings(db).set('gpsInterval', 5);
    await db.close();
    db = BikeComputerDatabase(executor: NativeDatabase(file));
    final settings = AppSettings(db);
    await settings.load();
    expect(settings.value('gpsInterval', 2), 5);
    expect(
      SessionCodec.decode((await db.getDocument('active', 'ride'))!)
          .totalDistance,
      3,
    );
    expect(await db.getDocument('routes', 'route'), 'local');
    await db.close();
    await dir.delete(recursive: true);
  });
  test('save transaction clears checkpoint only after durable write', () async {
    final db = BikeComputerDatabase(executor: NativeDatabase.memory());
    await db.putDocument('active', 'ride', 'checkpoint');
    await RideHistoryService(database: db)
        .saveRide(const RideSession(id: 'save', state: RideState.finished));
    expect(await db.getDocument('active', 'ride'), isNull);
    expect(await db.getDocument('ride', 'save'), isNotNull);
    await db.close();
  });
  test('deleting history preserves routes', () async {
    final db = BikeComputerDatabase(executor: NativeDatabase.memory());
    final h = RideHistoryService(database: db);
    await h.saveRide(const RideSession(id: 'one', state: RideState.finished));
    await db.putDocument('routes', 'kept', 'track');
    await h.clearHistory();
    expect(await db.getAllRides(), isEmpty);
    expect(await db.getDocument('routes', 'kept'), 'track');
    await db.close();
  });
  testWidgets('history opens a saved ride and confirms clear', (tester) async {
    final db = BikeComputerDatabase(executor: NativeDatabase.memory());
    final h = RideHistoryService(database: db);
    await h.saveRide(
      const RideSession(
        id: 'ui',
        state: RideState.finished,
        totalDistance: 9.8,
      ),
    );
    await tester.pumpWidget(MaterialApp(home: HistoryScreen(service: h)));
    await tester.pumpAndSettle();
    expect(find.text('Ride #1'), findsOneWidget);
    await tester.tap(find.byTooltip('Ritgeschiedenis wissen'));
    await tester.pumpAndSettle();
    expect(find.text('Alle ritten verwijderen?'), findsOneWidget);
    await tester.tap(find.text('Verwijderen'));
    await tester.pumpAndSettle();
    expect(find.text('Nog geen ritten'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await db.close();
  });
}
