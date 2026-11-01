import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:bike_computer/database/bike_computer_database.dart';
import 'package:bike_computer/core/settings.dart';
import 'package:bike_computer/core/storage/app_storage.dart';
import 'package:bike_computer/models/ride_session.dart';
import 'package:bike_computer/services/gps/gps_service.dart';
import 'package:bike_computer/services/bluetooth/ble_sensor_manager.dart';
import 'package:bike_computer/services/ride/ride_recording_service.dart';
import 'package:bike_computer/services/ride/session_codec.dart';

class RideController extends ChangeNotifier {
  final BikeComputerDatabase database;
  final AppSettings settings;
  final BleSensorManager sensors;
  final GPSService? injectedGps;
  final bool simulate;
  RideController(
    this.database,
    this.settings,
    this.sensors, {
    this.injectedGps,
    this.simulate = false,
  });
  RideRecordingService? _service;
  RideRecordingService get service => _service!;
  RideSession get session =>
      _service?.currentSession ?? const RideSession(state: RideState.idle);
  GPSService? gps;
  String profile = 'road_default';
  String? message;
  RideSession? recovery;
  int drinks = 0, foods = 0;
  DateTime? _checkpoint, _lastDrink, _lastFood;
  StreamSubscription<RideSession>? _events;
  StreamSubscription<String>? _warnings;
  Future<void> writes = Future.value();
  Future<void>? _initializing;
  bool _disposed = false;
  Future<void> initialize() => _initializing ??= _initialize();
  Future<void> _initialize() async {
    profile =
        await const AppStorage().readSelectedProfileId() ?? 'road_default';
    gps =
        injectedGps ??
        (simulate && kDebugMode
            ? MockGPSService()
            : RealGPSService(
                intervalSeconds: settings.value('gpsInterval', 2),
                highAccuracy: settings.value('highAccuracy', true),
              ));
    _service = RideRecordingService(
      gpsService: gps!,
      bleSensorManager: sensors,
      autoPause: settings.value('autoPause', false),
      maxAccuracy: settings.value('maxAccuracy', 50.0),
    );
    var previous = 0;
    _events = service.sessionStream.listen((s) {
      if (_disposed) return;
      if (s.trackPoints.length > previous &&
          (message?.startsWith('GPS') == true ||
              message?.startsWith('Wachten op actuele GPS') == true)) {
        message = null;
      }
      previous = s.trackPoints.length;
      final now = DateTime.now();
      if (s.startTime != null &&
          s.state != RideState.saved &&
          (_checkpoint == null ||
              now.difference(_checkpoint!).inSeconds >= 5 ||
              s.state == RideState.finished)) {
        _checkpoint = now;
        final raw = SessionCodec.encode(s);
        writes = writes
            .then(
              (_) => database.transaction(() async {
                await database.putDocument(
                  simulate ? 'simulation' : 'active',
                  'ride',
                  raw,
                );
                await database.putDocument(
                  'active',
                  'nutrition',
                  jsonEncode({'drinks': drinks, 'food': foods}),
                );
              }),
            )
            .catchError((Object e) {
              if (_disposed) return;
              message = 'Checkpoint mislukt: $e';
              notifyListeners();
            });
      }
      if (s.isRecording && s.startTime != null) {
        for (final p in [('drinkMinutes', true), ('foodMinutes', false)]) {
          final interval = settings.value(p.$1, 0);
          final last = p.$2 ? _lastDrink : _lastFood;
          if (interval > 0 &&
              now.difference(last ?? s.startTime!).inMinutes >= interval) {
            message = p.$2 ? 'Drinkherinnering' : 'Voedingsherinnering';
            if (p.$2) {
              _lastDrink = now;
            } else {
              _lastFood = now;
            }
          }
        }
      }
      notifyListeners();
    });
    _warnings = service.warnings.listen((e) {
      if (_disposed) return;
      message = e;
      notifyListeners();
    });
    await service.initializeRide();
    if (!simulate) {
      final raw = await database.getDocument('active', 'ride');
      if (raw != null) recovery = SessionCodec.decode(raw);
    }
  }

  Future<void> restore(bool yes) async {
    if (yes && recovery != null) {
      service.restore(recovery!);
      final nutrition = await database.getDocument('active', 'nutrition');
      if (nutrition != null) {
        final j = jsonDecode(nutrition);
        drinks = j['drinks'] ?? 0;
        foods = j['food'] ?? 0;
      }
    } else {
      await database.removeDocument('active', 'ride');
    }
    recovery = null;
    notifyListeners();
  }

  Future<void> start() async {
    await initialize();
    if (session.state == RideState.ready || session.state == RideState.saved) {
      profile =
          await const AppStorage().readSelectedProfileId() ?? 'road_default';
    }
    if (session.state == RideState.saved) {
      await service.discardRide();
      await service.initializeRide();
      drinks = 0;
      foods = 0;
      _checkpoint = null;
    }
    if (session.state == RideState.ready) {
      final raw = await database.getDocument('profiles', 'all');
      if (raw != null) {
        final p = (jsonDecode(raw) as List)
            .where((p) => p['id'] == profile)
            .firstOrNull;
        if (p != null) {
          service.autoPause = p['autoPause'];
          service.pauseSpeedKmh = (p['pauseSpeed'] as num).toDouble();
        }
      }
    }
    message = null;
    await service.startRecording();
  }

  void addDrink() {
    drinks++;
    notifyListeners();
  }

  void addFood() {
    foods++;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _events?.cancel();
    _warnings?.cancel();
    _service?.dispose();
    if (gps is RealGPSService) (gps as RealGPSService).dispose();
    if (gps is MockGPSService) (gps as MockGPSService).dispose();
    super.dispose();
  }
}
