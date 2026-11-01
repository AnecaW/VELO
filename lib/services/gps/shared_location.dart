import 'dart:async';

import '../../models/gps_models.dart';
import 'gps_service.dart';

/// Independent leases share one foreground GPS stream and wake lock.
class LocationHub {
  final GPSService source;
  final Set<Object> _owners = {};
  Future<void> _operations = Future.value();
  LocationHub(this.source);
  GPSService lease() => _LocationLease(this);
  Future<void> _change(Object owner, bool active) {
    final task = _operations.then((_) async {
      if (active) {
        if (_owners.contains(owner)) return;
        if (_owners.isEmpty) await source.startListening();
        _owners.add(owner);
      } else {
        _owners.remove(owner);
        if (_owners.isEmpty) await source.stopListening();
      }
    });
    _operations = task.catchError((Object _) {});
    return task;
  }
}

class _LocationLease implements GPSService {
  final LocationHub hub;
  _LocationLease(this.hub);
  @override
  Stream<GPSLocation> get locationStream => hub.source.locationStream;
  @override
  GPSLocation? getLastLocation() => hub.source.getLastLocation();
  @override
  Future<bool> isAvailable() => hub.source.isAvailable();
  @override
  Future<void> startListening() => hub._change(this, true);
  @override
  Future<void> stopListening() => hub._change(this, false);
}
