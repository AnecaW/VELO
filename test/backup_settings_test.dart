import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bike_computer/database/bike_computer_database.dart';
import 'package:bike_computer/core/settings.dart';
import 'package:bike_computer/services/storage/backup_service.dart';
import 'package:bike_computer/models/ride_session.dart';
import 'package:bike_computer/services/ride/ride_history_service.dart';

void main() {
  test('concurrent preference writes retain both values', () async {
    final db = BikeComputerDatabase(executor: NativeDatabase.memory());
    final settings = AppSettings(db);
    await Future.wait([
      settings.set('imperial', true),
      settings.set('gpsInterval', 5),
    ]);
    final restored = AppSettings(db);
    await restored.load();
    expect(restored.value('imperial', false), true);
    expect(restored.value('gpsInterval', 2), 5);
    await db.close();
  });
  test(
    'backup roundtrip preserves rides without duplicating or losing checkpoint',
    () async {
      final db = BikeComputerDatabase(executor: NativeDatabase.memory());
      await RideHistoryService(database: db).saveRide(
        const RideSession(
          id: 'backup',
          state: RideState.finished,
          totalDistance: 5,
        ),
      );
      await db.putDocument('active', 'ride', 'active-checkpoint');
      final service = BackupService(db);
      final archive = await service.export();
      await service.restore(archive);
      expect((await db.getAllRides()).length, 1);
      expect(await db.getDocument('active', 'ride'), 'active-checkpoint');
      expect(jsonDecode(archive)['version'], 1);
      await db.close();
    },
  );
  test('invalid backup fails before modifying existing database', () async {
    final db = BikeComputerDatabase(executor: NativeDatabase.memory());
    await db.putDocument('routes', 'kept', 'value');
    await expectLater(
      BackupService(db).restore('{"version":99}'),
      throwsFormatException,
    );
    expect(await db.getDocument('routes', 'kept'), 'value');
    await db.close();
  });
  test('v1 database migrates on reopen without deleting history', () async {
    final directory = await Directory.systemTemp.createTemp(
      'bike-migration-test',
    );
    final file = File('${directory.path}/legacy.sqlite');
    var db = BikeComputerDatabase(executor: NativeDatabase(file));
    await RideHistoryService(database: db).saveRide(
      const RideSession(
        id: 'legacy',
        state: RideState.finished,
        totalDistance: 42,
      ),
    );
    await db.close();
    final legacy = sqlite3.open(file.path);
    legacy.execute('DROP TABLE documents');
    legacy.execute('PRAGMA user_version=1');
    legacy.close();
    db = BikeComputerDatabase(executor: NativeDatabase(file));
    expect((await db.getAllRides()).single.totalDistance, 42);
    await db.putDocument('settings', 'app', '{}');
    expect(await db.getDocument('settings', 'app'), '{}');
    await db.close();
    await directory.delete(recursive: true);
  });
}
