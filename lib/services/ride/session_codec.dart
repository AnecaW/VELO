import 'dart:convert';

import 'package:bike_computer/models/ride_session.dart';
import 'package:bike_computer/models/gps_models.dart';

/// Versioned durable snapshot, shared by history and recovery checkpoints.
class SessionCodec {
  static String encode(RideSession s) => jsonEncode({
    'v': 1,
    'id': s.id,
    'state': s.state.name,
    'start': s.startTime?.toIso8601String(),
    'end': s.endTime?.toIso8601String(),
    'elapsed': s.elapsedTime.inMilliseconds,
    'moving': s.movingTime.inMilliseconds,
    'paused': s.pausedTime.inMilliseconds,
    'distance': s.totalDistance,
    'speed': s.currentSpeed,
    'average': s.averageSpeed,
    'max': s.maxSpeed,
    'gain': s.totalElevationGain,
    'loss': s.totalElevationLoss,
    'altitude': s.currentElevation,
    'grade': s.currentGrade,
    'averageGrade': s.averageGrade,
    'hr': s.averageHeartRate,
    'maxHr': s.maxHeartRate,
    'cadence': s.averageCadence,
    'maxCadence': s.maxCadence,
    'power': s.averagePower,
    'maxPower': s.maxPower,
    'points': s.trackPoints
        .map(
          (p) => [
            p.latitude,
            p.longitude,
            p.altitude,
            p.timestamp.toIso8601String(),
            p.speed,
            p.accuracy,
            p.heading,
            p.segmentStart,
          ],
        )
        .toList(),
  });

  static RideSession decode(String source) {
    final j = jsonDecode(source) as Map<String, dynamic>;
    if (j['v'] != 1) throw const FormatException('Unknown ride format');
    double n(String k) => (j[k] as num?)?.toDouble() ?? 0;
    double? optional(String k) => (j[k] as num?)?.toDouble();
    return RideSession(
      id: j['id'],
      state: RideState.values.byName(j['state']),
      startTime: DateTime.tryParse(j['start'] ?? ''),
      endTime: DateTime.tryParse(j['end'] ?? ''),
      elapsedTime: Duration(milliseconds: j['elapsed'] ?? 0),
      movingTime: Duration(milliseconds: j['moving'] ?? 0),
      pausedTime: Duration(milliseconds: j['paused'] ?? 0),
      totalDistance: n('distance'),
      currentSpeed: n('speed'),
      averageSpeed: n('average'),
      maxSpeed: n('max'),
      totalElevationGain: n('gain'),
      totalElevationLoss: n('loss'),
      currentElevation: n('altitude'),
      currentGrade: n('grade'),
      averageGrade: n('averageGrade'),
      averageHeartRate: optional('hr'),
      maxHeartRate: optional('maxHr'),
      averageCadence: optional('cadence'),
      maxCadence: optional('maxCadence'),
      averagePower: optional('power'),
      maxPower: optional('maxPower'),
      trackPoints: (j['points'] as List)
          .map(
            (p) => TrackPoint(
              latitude: (p[0] as num).toDouble(),
              longitude: (p[1] as num).toDouble(),
              altitude: (p[2] as num).toDouble(),
              timestamp: DateTime.parse(p[3]),
              speed: (p[4] as num?)?.toDouble(),
              accuracy: (p[5] as num?)?.toDouble(),
              heading: p.length > 6 ? (p[6] as num?)?.toDouble() : null,
              segmentStart: p.length > 7 ? p[7] as bool : false,
            ),
          )
          .toList(),
    );
  }
}
