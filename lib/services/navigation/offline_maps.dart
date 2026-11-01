import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:bike_computer/services/navigation/map_provider.dart';
import 'package:bike_computer/core/platform_bridge.dart';

class OfflineMaps extends ChangeNotifier {
  static final instance = OfflineMaps();
  List<ml.OfflineRegion> regions = [];
  final statuses = <int, ml.OfflineRegionStatus>{};
  String? error;
  bool starting = false;
  Timer? timer;
  Future<void> load() async {
    await configureMapNetworking();
    regions = await ml.getListOfRegions();
    for (final r in regions) {
      statuses[r.id] = await ml.getOfflineRegionStatus(r.id);
    }
    notifyListeners();
  }

  Future<void> download(
    String name,
    DownloadBounds area,
    MapStyleSpec style,
  ) async {
    area.validate();
    if (!style.offline) {
      throw StateError('Deze provider heeft geen toegestane gebiedsdownload');
    }
    if (starting) throw StateError('Een download wordt al voorbereid');
    starting = true;
    error = null;
    notifyListeners();
    try {
      await configureMapNetworking();
      final diagnostic = await PlatformBridge.call<Map>('diagnostics');
      if ((diagnostic?['freeBytes'] as num? ?? 0) < 100 * 1024 * 1024) {
        throw StateError('Minstens 100 MB vrije opslag nodig');
      }
      await ml.downloadOfflineRegion(
        ml.OfflineRegionDefinition(
          bounds: area.bounds,
          mapStyleUrl: style.url,
          minZoom: area.minZoom.toDouble(),
          maxZoom: area.maxZoom.toDouble(),
        ),
        metadata: {
          'name': name,
          'created': DateTime.now().toIso8601String(),
          'style': style.name,
          'provider': style.provider,
        },
        onEvent: (event) {
          if (event is ml.Error) {
            error = event.cause.message;
            notifyListeners();
          }
          if (event is ml.InProgress &&
              event.completedResourceSize > 48 * 1024 * 1024) {
            error = 'Downloadlimiet van 48 MB bereikt';
            _limit();
          }
        },
      );
      await load();
      timer?.cancel();
      timer = Timer.periodic(const Duration(seconds: 2), (_) => refresh());
    } catch (e) {
      error = e.toString();
      rethrow;
    } finally {
      starting = false;
      notifyListeners();
    }
  }

  Future<void> _limit() async {
    regions = await ml.getListOfRegions();
    for (final r in regions) {
      await ml.pauseOfflineRegionDownload(r.id);
    }
  }

  Future<void> refresh() async {
    try {
      for (final r in regions) {
        final s = await ml.getOfflineRegionStatus(r.id);
        statuses[r.id] = s;
        if (s.completedResourceSize > 48 * 1024 * 1024) {
          await ml.pauseOfflineRegionDownload(r.id);
          error = 'Gebied gepauzeerd: opslaglimiet';
        }
      }
      notifyListeners();
      if (statuses.isNotEmpty && statuses.values.every((s) => s.isComplete)) {
        timer?.cancel();
      }
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }
  }

  Future<void> pause(int id) async {
    await ml.pauseOfflineRegionDownload(id);
    await refresh();
  }

  Future<void> resume(int id) async {
    error = null;
    await ml.resumeOfflineRegionDownload(id);
    timer?.cancel();
    timer = Timer.periodic(const Duration(seconds: 2), (_) => refresh());
    await refresh();
  }

  Future<void> remove(int id) async {
    await ml.pauseOfflineRegionDownload(id);
    await ml.deleteOfflineRegion(id);
    statuses.remove(id);
    await load();
  }
}
