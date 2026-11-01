import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:bike_computer/database/bike_computer_database.dart';

class AppSettings extends ChangeNotifier {
  AppSettings(this.database);
  final BikeComputerDatabase database;
  final Map<String, dynamic> _values = {};
  T value<T>(String key, T fallback) =>
      _values[key] is T ? _values[key] as T : fallback;
  Future<void> load() async {
    _values.clear();
    final raw = await database.getDocument('settings', 'app');
    if (raw != null) _values.addAll(jsonDecode(raw) as Map<String, dynamic>);
    notifyListeners();
  }

  Future<void> _writes = Future.value();
  Future<void> set(String key, dynamic value) {
    final task = _writes.then((_) async {
      final next = {..._values, key: value};
      await database.putDocument('settings', 'app', jsonEncode(next));
      _values[key] = value;
      notifyListeners();
    });
    _writes = task.catchError((Object _) {});
    return task;
  }

  List<String> fields(String profile) =>
      value<List<dynamic>>('fields-$profile', [
        'Speed',
        'Distance',
        'Moving time',
        'Elapsed',
        'Average',
        'Max speed',
        'Heart rate',
        'Cadence',
        'Power',
        'Climb',
        'Altitude',
        'Grade',
      ]).cast<String>();
}
