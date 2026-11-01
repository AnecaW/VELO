import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:bike_computer/services/gps/gps_service.dart';

class LocationPlatform extends GeolocatorPlatform {
  final controller = StreamController<Position>.broadcast();
  int subscriptions = 0;
  bool enabled = true;
  @override
  Future<bool> isLocationServiceEnabled() async => enabled;
  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;
  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    subscriptions++;
    return controller.stream;
  }
}

void main() {
  test('GPS provider interruption reconnects while wanted and stops retrying after stop', () async {
    final previous = GeolocatorPlatform.instance;
    final platform = LocationPlatform();
    GeolocatorPlatform.instance = platform;
    final gps = RealGPSService(retryDelay: const Duration(milliseconds: 5));
    final errors = <Object>[];
    final subscription = gps.locationStream.listen((_) {}, onError: errors.add);
    try {
      await gps.startListening();
      expect(platform.subscriptions, 1);
      platform.controller.addError(
        StateError('test GPS provider disconnected'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(errors, isNotEmpty);
      expect(platform.subscriptions, 2);
      await gps.stopListening();
      platform.controller.addError(StateError('test GPS stopped'));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(platform.subscriptions, 2);
    } finally {
      await subscription.cancel();
      await gps.dispose();
      await platform.controller.close();
      GeolocatorPlatform.instance = previous;
    }
  });
}
