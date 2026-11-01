import 'dart:io';
import 'dart:async';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

part 'bike_computer_database.g.dart';

class RideHistoryTable extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get rideId => text().unique()();
  TextColumn get state => text()();
  DateTimeColumn get startTime => dateTime().nullable()();
  DateTimeColumn get endTime => dateTime().nullable()();
  RealColumn get totalDistance => real()();
  RealColumn get averageSpeed => real()();
  RealColumn get maxSpeed => real()();
  RealColumn get totalElevationGain => real()();
  RealColumn get totalElevationLoss => real()();
  RealColumn get averageGrade => real()();
  RealColumn get averageHeartRate => real().nullable()();
  RealColumn get maxHeartRate => real().nullable()();
  RealColumn get averageCadence => real().nullable()();
  RealColumn get maxCadence => real().nullable()();
  RealColumn get averagePower => real().nullable()();
  RealColumn get maxPower => real().nullable()();
  IntColumn get elapsedSeconds => integer()();
}

@DriftDatabase(tables: [RideHistoryTable])
class BikeComputerDatabase extends _$BikeComputerDatabase {
  final _documentChanges = StreamController<String>.broadcast();
  Stream<String> get documentChanges => _documentChanges.stream;
  void documentsChanged(String category) {
    if (!_documentChanges.isClosed) _documentChanges.add(category);
  }

  BikeComputerDatabase({QueryExecutor? executor})
    : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createStorage();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) await _createStorage();
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA busy_timeout = 10000');
    },
  );

  /// Serializes secure-token rotation across foreground/background isolates.
  Future<void> withAccountRefreshLock(Future<void> Function() action) async {
    String? acquired;
    for (var attempt = 0; attempt < 400; attempt++) {
      final now = DateTime.now().microsecondsSinceEpoch;
      final lease = '${now + 30000000}:${Random.secure().nextInt(1 << 32)}';
      await customStatement(
        "INSERT INTO documents(category,key,value) VALUES('account-lock','refresh',?) ON CONFLICT(category,key) DO UPDATE SET value=excluded.value WHERE CAST(documents.value AS INTEGER)<=?",
        [lease, now],
      );
      if (await getDocument('account-lock', 'refresh') == lease) {
        acquired = lease;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (acquired == null) {
      throw StateError('Account is tijdelijk bezig. Probeer opnieuw.');
    }
    try {
      await action();
    } finally {
      await customStatement(
        "DELETE FROM documents WHERE category='account-lock' AND key='refresh' AND value=?",
        [acquired],
      );
    }
  }

  Future<void> _createStorage() async {
    await customStatement(
      'CREATE TABLE IF NOT EXISTS documents (category TEXT NOT NULL, key TEXT NOT NULL, value TEXT NOT NULL, PRIMARY KEY(category, key))',
    );
  }

  Future<void> putDocument(String category, String key, String value) async {
    await customStatement(
      'INSERT INTO documents(category,key,value) VALUES(?,?,?) ON CONFLICT(category,key) DO UPDATE SET value=excluded.value',
      [category, key, value],
    );
    documentsChanged(category);
  }

  Future<String?> getDocument(String category, String key) async {
    final rows = await customSelect(
      'SELECT value FROM documents WHERE category=? AND key=?',
      variables: [Variable(category), Variable(key)],
    ).get();
    return rows.isEmpty ? null : rows.first.read<String>('value');
  }

  Future<Map<String, String>> documents(String category) async {
    final rows = await customSelect(
      'SELECT key,value FROM documents WHERE category=?',
      variables: [Variable(category)],
    ).get();
    return {
      for (final r in rows) r.read<String>('key'): r.read<String>('value'),
    };
  }

  Future<void> removeDocument(String category, String key) async {
    await customStatement('DELETE FROM documents WHERE category=? AND key=?', [
      category,
      key,
    ]);
    documentsChanged(category);
  }

  @override
  Future<void> close() async {
    await _documentChanges.close();
    await super.close();
  }

  Future<List<RideHistoryTableData>> getAllRides() =>
      select(rideHistoryTable).get();

  Future<int> insertRide(RideHistoryTableCompanion companion) =>
      into(rideHistoryTable).insert(companion);

  Future<bool> deleteRideByRideId(String rideId) async {
    final rowsDeleted = await (delete(
      rideHistoryTable,
    )..where((tbl) => tbl.rideId.equals(rideId))).go();
    return rowsDeleted > 0;
  }

  Future<void> deleteRideHistory() async {
    await delete(rideHistoryTable).go();
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    final file = File('${directory.path}/bike_computer.sqlite');
    return NativeDatabase.createInBackground(file);
  });
}
