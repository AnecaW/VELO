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
  RealGPSService({this.intervalSeconds = 2, this.highAccuracy = true});
  final _locationController = StreamController<GPSLocation>.broadcast();
  GPSLocation? _lastLocation;
  bool _isListening = false;
  StreamSubscription<Position>? _positionSubscription;

  @override
  Stream<GPSLocation> get locationStream => _locationController.stream;

  @override
  Future<void> startListening() async {
    if (_isListening) return;

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw GPSException(
        message: 'Location services are disabled. Enable GPS to continue.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw GPSException(
        message: 'Location permission is required to record GPS data.',
      );
    }

    _isListening = true;
    _positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: Platform.isAndroid
              ? AndroidSettings(
                  accuracy: highAccuracy
                      ? LocationAccuracy.best
                      : LocationAccuracy.medium,
                  distanceFilter: 0,
                  intervalDuration: Duration(seconds: intervalSeconds),
                  foregroundNotificationConfig:
                      const ForegroundNotificationConfig(
                        notificationTitle: 'Ultimate Bike Computer',
                        notificationText: 'Ritregistratie actief · open om te pauzeren of stoppen',
                        enableWakeLock: true,
                        setOngoing: true,
                      ),
                )
              : const LocationSettings(
                  accuracy: LocationAccuracy.best,
                  distanceFilter: 0,
                ),
        ).listen(
          (position) {
            final gpsLocation = GPSLocation(
              latitude: position.latitude,
              longitude: position.longitude,
              altitude: position.altitude,
              accuracy: position.accuracy,
              speed: position.speed.isFinite ? position.speed : 0.0,
              heading: position.heading.isFinite ? position.heading : 0.0,
              timestamp: position.timestamp,
            );

            _lastLocation = gpsLocation;
            _locationController.add(gpsLocation);
          },
          onError: (error) {
            _isListening = false;
            _locationController.addError(
              GPSException(
                message: 'GPS stream error: $error',
                originalException: error,
              ),
            );
          },
        );
  }

  @override
  Future<void> stopListening() async {
    _isListening = false;
    await _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  @override
  GPSLocation? getLastLocation() => _lastLocation;

  @override
  Future<bool> isAvailable() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  Future<void> dispose() async {
    await stopListening();
    await _locationController.close();
  }
}
