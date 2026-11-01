import 'package:bike_computer/core/runtime.dart';
import 'package:bike_computer/services/ride/session_codec.dart';
import 'package:drift/drift.dart';
import 'package:bike_computer/database/bike_computer_database.dart';
import 'package:bike_computer/models/ride_session.dart';

/// Service for managing ride history
class RideHistoryService {
  static final RideHistoryService _instance = RideHistoryService._internal();

  factory RideHistoryService({BikeComputerDatabase? database}) {
    if (database != null) {
      return RideHistoryService._withDatabase(database);
    }
    return _instance;
  }

  RideHistoryService._internal() : database = Runtime.database;

  RideHistoryService._withDatabase(this.database);

  final BikeComputerDatabase database;
  final List<RideSession> _rides = [];

  Future<void> loadPersistedRides() async {
    final rows = await database.getAllRides();
    _rides
      ..clear()
      ..addAll(rows.map(_fromRow));
    for (var i = 0; i < _rides.length; i++) {
      final payload = await database.getDocument('ride', _rides[i].id!);
      if (payload != null) _rides[i] = SessionCodec.decode(payload);
    }
  }

  /// Get all saved rides
  List<RideSession> getAllRides() {
    return List.unmodifiable(_rides);
  }

  /// Get rides sorted by date (newest first)
  List<RideSession> getRidesSortedByDate() {
    final sorted = List<RideSession>.from(_rides);
    sorted.sort(
      (a, b) =>
          (b.endTime ?? DateTime.now()).compareTo(a.endTime ?? DateTime.now()),
    );
    return sorted;
  }

  /// Get a ride by ID
  RideSession? getRideById(String id) {
    try {
      return _rides.firstWhere((ride) => ride.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Save a ride
  Future<String> saveRide(RideSession ride) async {
    final id =
        ride.id ??
        'ride-${ride.startTime?.microsecondsSinceEpoch ?? DateTime.now().microsecondsSinceEpoch}';
    if (await database.getDocument('ride', id) != null) return id;
    final savedRide = ride.copyWith(id: id, state: RideState.saved);

    await database.transaction(() async {
      await database.insertRide(
        RideHistoryTableCompanion(
          rideId: Value(id),
          state: Value(savedRide.state.name),
          startTime: Value(savedRide.startTime),
          endTime: Value(savedRide.endTime),
          totalDistance: Value(savedRide.totalDistance),
          averageSpeed: Value(savedRide.averageSpeed),
          maxSpeed: Value(savedRide.maxSpeed),
          totalElevationGain: Value(savedRide.totalElevationGain),
          totalElevationLoss: Value(savedRide.totalElevationLoss),
          averageGrade: Value(savedRide.averageGrade),
          averageHeartRate: Value(savedRide.averageHeartRate),
          maxHeartRate: Value(savedRide.maxHeartRate),
          averageCadence: Value(savedRide.averageCadence),
          maxCadence: Value(savedRide.maxCadence),
          averagePower: Value(savedRide.averagePower),
          maxPower: Value(savedRide.maxPower),
          elapsedSeconds: Value(savedRide.elapsedTime.inSeconds),
        ),
      );

      await database.putDocument('ride', id, SessionCodec.encode(savedRide));
      await database.removeDocument('active', 'ride');
    });
    await loadPersistedRides();
    return id;
  }

  /// Delete a ride
  Future<bool> deleteRide(String id) async {
    final deleted = await database.transaction(() async {
      await database.removeDocument('ride', id);
      return database.deleteRideByRideId(id);
    });
    if (deleted) {
      _rides.removeWhere((ride) => ride.id == id);
      return true;
    }

    final index = _rides.indexWhere((ride) => ride.id == id);
    if (index != -1) {
      _rides.removeAt(index);
      return true;
    }
    return false;
  }

  /// Get total statistics
  ({int totalRides, double totalDistance, Duration totalTime}) getStatistics() {
    double totalDistance = 0.0;
    Duration totalTime = Duration.zero;

    for (final ride in _rides) {
      totalDistance += ride.totalDistance;
      totalTime += ride.elapsedTime;
    }

    return (
      totalRides: _rides.length,
      totalDistance: totalDistance,
      totalTime: totalTime,
    );
  }

  /// Clear all rides
  Future<void> clearHistory() async {
    await database.transaction(() async {
      await database.deleteRideHistory();
      await database.customStatement(
        "DELETE FROM documents WHERE category='ride'",
      );
    });
    _rides.clear();
  }

  RideSession _fromRow(RideHistoryTableData row) {
    final state = RideState.values.firstWhere(
      (value) => value.name == row.state,
      orElse: () => RideState.finished,
    );

    return RideSession(
      id: row.rideId,
      state: state,
      startTime: row.startTime,
      endTime: row.endTime,
      elapsedTime: Duration(seconds: row.elapsedSeconds),
      totalDistance: row.totalDistance,
      averageSpeed: row.averageSpeed,
      maxSpeed: row.maxSpeed,
      totalElevationGain: row.totalElevationGain,
      totalElevationLoss: row.totalElevationLoss,
      averageGrade: row.averageGrade,
      averageHeartRate: row.averageHeartRate,
      maxHeartRate: row.maxHeartRate,
      averageCadence: row.averageCadence,
      maxCadence: row.maxCadence,
      averagePower: row.averagePower,
      maxPower: row.maxPower,
    );
  }
}
