import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:bike_computer/database/bike_computer_database.dart';
import 'package:bike_computer/services/navigation/gpx_route.dart';
import 'package:bike_computer/services/ride/gpx_export_service.dart';
import 'package:bike_computer/services/ride/session_codec.dart';

class GpxExchangeService {
  final BikeComputerDatabase db;
  GpxExchangeService(this.db);
  Future<String> importRoute(String raw, {String? filename}) async {
    final route = parseGpx(raw), id = 'gpx:${sha256.convert(utf8.encode(raw))}';
    await db.transaction(() async {
      await db.putDocument('routes', id, route.encode());
      await db.putDocument(
        'route-source',
        id,
        jsonEncode({
          'source': 'GPX-import',
          'filename': filename,
          'imported': DateTime.now().toUtc().toIso8601String(),
        }),
      );
      await db.putDocument('gpx-original', id, raw);
    });
    return id;
  }

  Future<String> exportRide(String id) async {
    if (id.startsWith('strava:')) {
      throw const FormatException('Geen eigen opgenomen rit');
    }
    final raw = await db.getDocument('ride', id);
    if (raw == null) throw const FormatException('Volledige rit ontbreekt');
    final ride = SessionCodec.decode(raw);
    if (ride.trackPoints.isEmpty) {
      throw const FormatException('Geen GPS-spoor beschikbaar');
    }
    return GpxExportService.exportToGpx(ride);
  }
}
