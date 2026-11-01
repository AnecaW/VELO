import '../../models/bike_type.dart';

import 'dart:async';
import 'dart:math' as math;

import 'package:bike_computer/models/ride_session.dart';
import 'package:bike_computer/models/gps_models.dart';
import 'package:bike_computer/models/sensor_models.dart';
import 'package:bike_computer/services/bluetooth/ble_sensor_manager.dart';
import 'package:bike_computer/services/gps/gps_service.dart';
import 'package:bike_computer/services/ride/calculations.dart';

/// Injectable time and GPS allow deterministic recording tests.
class RideRecordingService {
  final GPSService gpsService;
  final BleSensorManager? bleSensorManager;
  final DateTime Function() now;
  bool autoPause;
  double pauseSpeedKmh;
  final double maxAccuracy, maxSpeedMs;
  RideRecordingService({
    required this.gpsService,
    this.bleSensorManager,
    DateTime Function()? now,
    this.autoPause = false,
    this.pauseSpeedKmh = 3,
    this.maxAccuracy = 50,
    this.maxSpeedMs = 40,
  }) : now = now ?? DateTime.now;
  RideSession _currentSession = const RideSession(state: RideState.idle);
  RideSession get currentSession => _currentSession;
  final _events = StreamController<RideSession>.broadcast();
  Stream<RideSession> get sessionStream => _events.stream;
  final _warnings = StreamController<String>.broadcast();
  Stream<String> get warnings => _warnings.stream;
  Timer? _timer;
  StreamSubscription<GPSLocation>? _gps;
  StreamSubscription<SensorReading>? _sensors;
  DateTime? _lastTick, _lastFix, _lowSpeedSince;
  GPSLocation? _previous;
  double? _elevationAnchor;
  final _altitudes = <double>[];
  bool _automaticPause = false, _busy = false;
  final Map<SensorType, DateTime> _sensorTimes = {};
  final Map<SensorType, double> _sums = {};
  final Map<SensorType, int> _counts = {};
  void _require(bool allowed) {
    if (!allowed || _busy) {
      throw StateError('Ongeldige actie vanuit ${_currentSession.state.name}');
    }
  }

  Future<void> initializeRide() async {
    _require(_currentSession.state == RideState.idle);
    _currentSession = const RideSession(state: RideState.ready);
    _emit();
  }

  void restore(RideSession session) {
    _require(
      _currentSession.state == RideState.idle ||
          _currentSession.state == RideState.ready,
    );
    _currentSession = session.copyWith(
      state: RideState.paused,
      currentSpeed: 0,
      clearSensors: true,
    );
    _lastTick = null;
    _previous = null;
    _emit();
  }

  void setBikeType(BikeType type) {
    _require(_currentSession.state == RideState.ready);
    _currentSession = _currentSession.copyWith(bikeType: type);
  }

  Future<void> startRecording() async {
    _require(
      _currentSession.state == RideState.ready ||
          _currentSession.state == RideState.paused,
    );
    if (_currentSession.state == RideState.paused) tick();
    _busy = true;
    final prior = _currentSession;
    try {
      _gps ??= gpsService.locationStream.listen(
        _onGPS,
        onError: (Object e) => _warnings.add('GPS: $e'),
      );
      await gpsService.startListening();
      _sensors ??= bleSensorManager?.sensorDataStream.listen(_onSensor);
      final time = now();
      _currentSession = prior.copyWith(
        state: RideState.recording,
        startTime: prior.startTime ?? time,
        id: prior.id ?? 'ride-${time.microsecondsSinceEpoch}',
      );
      _automaticPause = false;
      _lowSpeedSince = null;
      _previous = null;
      _elevationAnchor = null;
      _altitudes.clear();
      _lastTick = time;
      _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => tick());
      _emit();
    } catch (_) {
      await _gps?.cancel();
      _gps = null;
      await gpsService.stopListening();
      _currentSession = prior;
      rethrow;
    } finally {
      _busy = false;
    }
  }

  Future<void> pauseRecording() async {
    _require(_currentSession.state == RideState.recording);
    tick();
    _automaticPause = false;
    _previous = null;
    _currentSession = _currentSession.copyWith(
      state: RideState.paused,
      currentSpeed: 0,
    );
    _emit();
  }

  Future<void> stopRecording() async {
    _require(
      _currentSession.state == RideState.recording ||
          _currentSession.state == RideState.paused,
    );
    tick();
    _currentSession = _currentSession.copyWith(state: RideState.stopping);
    _emit();
    _timer?.cancel();
    _timer = null;
    try {
      await gpsService.stopListening();
    } catch (e) {
      _warnings.add('GPS stoppen: $e');
    }
    await _gps?.cancel();
    _gps = null;
    await _sensors?.cancel();
    _sensors = null;
    _currentSession = _currentSession.copyWith(
      state: RideState.finished,
      endTime: now(),
      currentSpeed: 0,
    );
    _emit();
  }

  Future<void> discardRide() async {
    _timer?.cancel();
    _timer = null;
    await gpsService.stopListening();
    await _gps?.cancel();
    _gps = null;
    await _sensors?.cancel();
    _sensors = null;
    _currentSession = const RideSession(state: RideState.idle);
    _emit();
  }

  void markAsSaved(String id) {
    _require(
      _currentSession.state == RideState.finished ||
          _currentSession.state == RideState.saving,
    );
    _currentSession = _currentSession.copyWith(state: RideState.saved, id: id);
    _emit();
  }

  /// Updates using actual elapsed time, not the number of timer callbacks.
  void tick() {
    final time = now();
    if (_lastTick == null) return;
    final delta = time.difference(_lastTick!);
    _lastTick = time;
    if (delta.isNegative) return;
    final recording = _currentSession.state == RideState.recording;
    final paused = _currentSession.state == RideState.paused;
    if (!recording && !paused) return;
    final fresh =
        _lastFix != null && time.difference(_lastFix!).inSeconds <= 10;
    final moving =
        recording && fresh && _currentSession.currentSpeed > pauseSpeedKmh;
    final movingTime =
        _currentSession.movingTime + (moving ? delta : Duration.zero);
    _currentSession = _currentSession.copyWith(
      elapsedTime: _currentSession.elapsedTime + delta,
      movingTime: movingTime,
      pausedTime: _currentSession.pausedTime + (paused ? delta : Duration.zero),
      currentSpeed: fresh ? _currentSession.currentSpeed : 0,
      clearHeartRate:
          _sensorTimes[SensorType.heartRate] != null &&
          time.difference(_sensorTimes[SensorType.heartRate]!).inSeconds > 10,
      clearCadence:
          _sensorTimes[SensorType.cadence] != null &&
          time.difference(_sensorTimes[SensorType.cadence]!).inSeconds > 10,
      clearPower:
          _sensorTimes[SensorType.power] != null &&
          time.difference(_sensorTimes[SensorType.power]!).inSeconds > 10,
      averageSpeed: SpeedCalculator.averageSpeed(
        _currentSession.totalDistance,
        movingTime,
      ),
    );
    if (recording && !fresh) {
      _warnings.add('Wachten op actuele GPS · geen afstand toegevoegd');
    }
    _emit();
  }

  void _onGPS(GPSLocation p) {
    final s = _currentSession.state;
    if (s != RideState.recording && s != RideState.paused) return;
    if (!p.latitude.isFinite ||
        !p.longitude.isFinite ||
        p.latitude.abs() > 90 ||
        p.longitude.abs() > 180 ||
        !p.accuracy.isFinite ||
        p.accuracy < 0 ||
        p.accuracy > maxAccuracy ||
        !p.speed.isFinite ||
        p.speed > maxSpeedMs ||
        (_lastFix != null && !p.timestamp.isAfter(_lastFix!))) {
      _warnings.add('GPS-punt geweigerd: kwaliteit of tijdstip');
      return;
    }
    var meters = 0.0;
    if (_previous != null) {
      final seconds =
          p.timestamp.difference(_previous!.timestamp).inMilliseconds / 1000;
      meters = DistanceCalculator.distanceInMeters(
        _previous!.latitude,
        _previous!.longitude,
        p.latitude,
        p.longitude,
      );
      if (seconds <= 0 || meters / seconds > maxSpeedMs) {
        _warnings.add('GPS-sprong genegeerd');
        return;
      }
      if (seconds > 30) {
        meters = 0;
        _previous = null;
        _elevationAnchor = null;
        _altitudes.clear();
      }
    }
    tick();
    _lastFix = p.timestamp;
    final speed = math.max(0.0, p.speed) * 3.6;
    if (autoPause) {
      if (s == RideState.recording && speed < pauseSpeedKmh) {
        _lowSpeedSince ??= p.timestamp;
        if (p.timestamp.difference(_lowSpeedSince!).inSeconds >= 5) {
          _automaticPause = true;
          _currentSession = _currentSession.copyWith(state: RideState.paused);
          _previous = null;
        }
      } else if (speed > pauseSpeedKmh + 1) {
        _lowSpeedSince = null;
        if (_automaticPause) {
          _currentSession = _currentSession.copyWith(
            state: RideState.recording,
          );
          _automaticPause = false;
          meters = 0;
        }
      }
    }
    if (_currentSession.state == RideState.paused) {
      _previous = null;
      _emit();
      return;
    }
    if (speed < 1.8) meters = 0;
    final distance = _currentSession.totalDistance + meters / 1000;
    var gain = _currentSession.totalElevationGain,
        loss = _currentSession.totalElevationLoss;
    var altitude = _currentSession.currentElevation, grade = 0.0;
    if (p.altitude.isFinite) {
      _altitudes.add(p.altitude);
      if (_altitudes.length > 5) _altitudes.removeAt(0);
      altitude = ElevationService.smoothElevation(_altitudes);
      _elevationAnchor ??= altitude;
      final delta = altitude - _elevationAnchor!;
      if (delta.abs() >= 3 && delta.abs() < 30) {
        if (delta > 0) {
          gain += delta;
        } else {
          loss -= delta;
        }
        _elevationAnchor = altitude;
      }
      if (meters >= 20) {
        grade = ((altitude - _currentSession.currentElevation) / meters * 100)
            .clamp(-35, 35);
      }
    }
    final segmentStart = _previous == null;
    _previous = p;
    _currentSession = _currentSession.copyWith(
      trackPoints: [
        ..._currentSession.trackPoints,
        p.toTrackPoint(segmentStart: segmentStart),
      ],
      totalDistance: distance,
      currentSpeed: speed,
      maxSpeed: math.max(_currentSession.maxSpeed, speed),
      averageSpeed: SpeedCalculator.averageSpeed(
        distance,
        _currentSession.movingTime,
      ),
      currentGpsAccuracy: p.accuracy,
      currentElevation: altitude,
      totalElevationGain: gain,
      totalElevationLoss: loss,
      currentGrade: grade,
      averageGrade: RideCalculator.calculateAverageGrade(gain, distance),
    );
    _emit();
  }

  void _onSensor(SensorReading r) {
    if (_currentSession.state != RideState.recording ||
        !r.value.isFinite ||
        r.value < 0) {
      return;
    }
    _sensorTimes[r.type] = r.timestamp;
    _sums[r.type] = (_sums[r.type] ?? 0) + r.value;
    _counts[r.type] = (_counts[r.type] ?? 0) + 1;
    final avg = _sums[r.type]! / _counts[r.type]!;
    _currentSession = _currentSession.copyWith(
      currentHeartRate: r.type == SensorType.heartRate ? r.value : null,
      averageHeartRate: r.type == SensorType.heartRate ? avg : null,
      maxHeartRate: r.type == SensorType.heartRate
          ? math.max(_currentSession.maxHeartRate ?? 0, r.value)
          : null,
      currentCadence: r.type == SensorType.cadence ? r.value : null,
      averageCadence: r.type == SensorType.cadence ? avg : null,
      maxCadence: r.type == SensorType.cadence
          ? math.max(_currentSession.maxCadence ?? 0, r.value)
          : null,
      currentPower: r.type == SensorType.power ? r.value : null,
      averagePower: r.type == SensorType.power ? avg : null,
      maxPower: r.type == SensorType.power
          ? math.max(_currentSession.maxPower ?? 0, r.value)
          : null,
    );
    _emit();
  }

  void _emit() {
    if (!_events.isClosed) _events.add(_currentSession);
  }

  void dispose() {
    _timer?.cancel();
    _gps?.cancel();
    _sensors?.cancel();
    gpsService.stopListening();
    _events.close();
    _warnings.close();
  }
}
