import 'dart:async';

import 'dart:io';

import 'package:geolocator/geolocator.dart';

import 'package:bike_computer/models/gps_models.dart';

import 'package:bike_computer/core/errors/exceptions.dart';

/// Abstract base for GPS service

abstract class GPSService {
  /// Stream of GPS location updates

  Stream<GPSLocation> get locationStream;

  /// Start listening to GPS updates

  Future<void> startListening();

  /// Stop listening to GPS updates

  Future<void> stopListening();

  /// Get last known location

  GPSLocation? getLastLocation();

  /// Check if GPS is available

  Future<bool> isAvailable();
}

/// Mock GPS service for development/testing

/// This can simulate GPS tracks without real hardware

class MockGPSService implements GPSService {
  final _locationController = StreamController<GPSLocation>.broadcast();

  GPSLocation? _lastLocation;

  bool _isListening = false;

  Timer? _simulationTimer;

  @override
  Stream<GPSLocation> get locationStream => _locationController.stream;

  @override
  Future<void> startListening() async {
    if (_isListening) return;

    _isListening = true;

    // Simulate a simple track with slight movement

    double lat = 51.2093;

    double lon = 4.4025; // Antwerp, Belgium

    double alt = 5.0;

    int counter = 0;

    _simulationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      // Simulate movement

      lat += 0.0001 * (counter % 2 == 0 ? 1 : -0.5);

      lon += 0.0001 * (counter % 3 == 0 ? 1 : -0.3);

      alt += (counter % 4 == 0 ? 0.5 : -0.2);

      counter++;

      _lastLocation = GPSLocation(
        latitude: lat,

        longitude: lon,

        altitude: alt,

        accuracy: 5.0 + (counter % 3) * 2, // Vary accuracy

        speed: 5.0 + (counter % 7 == 0 ? 2.0 : 0.0), // 5-7 m/s

        heading: (counter * 10) % 360,

        timestamp: DateTime.now(),
      );

      _locationController.add(_lastLocation!);
    });
  }

  @override
  Future<void> stopListening() async {
    if (!_isListening) return;

    _isListening = false;

    _simulationTimer?.cancel();
  }

  @override
  GPSLocation? getLastLocation() => _lastLocation;

  @override
  Future<bool> isAvailable() async => true;

  void dispose() {
    _simulationTimer?.cancel();

    _locationController.close();
  }
}

/// Real GPS service using platform GPS

class RealGPSService implements GPSService {
  final int intervalSeconds;
  final bool highAccuracy;
  final Duration retryDelay;
  final bool recording;
  final int Function()? intervalProvider;
  final bool Function()? accuracyProvider;
  final String? notificationTitle;
  RealGPSService({
    this.intervalProvider,
    this.accuracyProvider,
    this.notificationTitle,
    this.intervalSeconds = 2,
    this.highAccuracy = true,
    this.recording = false,
    this.retryDelay = const Duration(seconds: 5),
  });
  final _locationController = StreamController<GPSLocation>.broadcast();
  GPSLocation? _lastLocation;
  bool _isListening = false, _wanted = false;
  int _generation = 0;
  Timer? _retry;
  StreamSubscription<Position>? _positionSubscription;
  @override
  Stream<GPSLocation> get locationStream => _locationController.stream;
  @override
  Future<void> startListening() async {
    if (_isListening) return;
    final generation = _generation;
    _wanted = true;
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw GPSException(
        message: 'Locatie staat uit. Zet GPS aan om je rit op te nemen.',
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw GPSException(
        message: 'Sta locatie toe om je rit op te nemen. Opgeslagen ritten blijven beschikbaar.',
      );
    }
    if (generation != _generation) return;
    await _positionSubscription?.cancel();
    if (generation != _generation) return;
    _isListening = true;
    _positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: Platform.isAndroid
              ? AndroidSettings(
                  useMSLAltitude: false,
                  accuracy: (accuracyProvider?.call() ?? highAccuracy)
                      ? LocationAccuracy.best
                      : LocationAccuracy.medium,
                  distanceFilter: 0,
                  intervalDuration: Duration(
                    seconds: intervalProvider?.call() ?? intervalSeconds,
                  ),
                  foregroundNotificationConfig: ForegroundNotificationConfig(
                    notificationTitle:
                        notificationTitle ??
                        (recording
                            ? 'VELO · ritregistratie'
                            : 'VELO · locatie'),
                    notificationText:
                        'Locatie actief · open VELO om te pauzeren of stoppen',
                    enableWakeLock: true,
                    setOngoing: true,
                  ),
                )
              : const LocationSettings(
                  accuracy: LocationAccuracy.best,
                  distanceFilter: 0,
                ),
        ).listen(
          (p) {
            _lastLocation = GPSLocation(
              latitude: p.latitude,
              longitude: p.longitude,
              altitude: p.altitude,
              accuracy: p.accuracy,
              speed: p.speed.isFinite ? p.speed : 0,
              heading: p.heading.isFinite ? p.heading : 0,
              timestamp: p.timestamp,
            );
            _locationController.add(_lastLocation!);
          },
          onError: (Object error) {
            _isListening = false;
            if (_wanted) {
              _locationController.addError(
                GPSException(
                  message:
                      'GPS tijdelijk niet beschikbaar. VELO probeert opnieuw.',
                ),
              );
              _scheduleRetry();
            }
          },
          onDone: () {
            _isListening = false;
            _scheduleRetry();
          },
        );
  }

  void _scheduleRetry() {
    if (!_wanted || _retry?.isActive == true) return;
    _retry = Timer(retryDelay, () async {
      if (!_wanted) return;
      try {
        final available = await isAvailable();
        if (_wanted && available) await startListening();
      } catch (_) {}
      if (_wanted && !_isListening) _scheduleRetry();
    });
  }

  @override
  Future<void> stopListening() async {
    _wanted = false;
    _generation++;
    _retry?.cancel();
    _isListening = false;
    await _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  @override
  GPSLocation? getLastLocation() => _lastLocation;
  @override
  Future<bool> isAvailable() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  Future<void> dispose() async {
    await stopListening();
    await _locationController.close();
  }
}
