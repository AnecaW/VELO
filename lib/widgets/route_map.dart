import 'package:bike_computer/core/runtime.dart';
import 'package:bike_computer/widgets/vector_route_map.dart';

import 'dart:math' as math;
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:bike_computer/services/navigation/gpx_route.dart';

/// Raster MBTiles are read locally; this provider never downloads tiles.
class MbTilesProvider extends TileProvider {
  final Database database;
  MbTilesProvider(String path) : database = _open(path);
  static Database _open(String path) {
    final db = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      db.select('SELECT tile_data FROM tiles LIMIT 1');
      return db;
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final rows = database.select(
      'SELECT tile_data FROM tiles WHERE length(tile_data)<2097152 AND zoom_level=? AND tile_column=? AND tile_row=? LIMIT 1',
      [coordinates.z, coordinates.x, (1 << coordinates.z) - 1 - coordinates.y],
    );
    final bytes = rows.isEmpty
        ? base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
          )
        : rows.first['tile_data'] as Uint8List;
    return MemoryImage(bytes);
  }

  @override
  Future<void> dispose() async {
    database.close();
  }
}

class RouteMap extends StatefulWidget {
  final NavRoute? route;
  final LatLng? position;
  final LatLng? destination;
  final ValueChanged<LatLng>? onTap;
  final bool online;
  final double heading;
  final bool followPosition;
  final String? offlinePath;
  final ValueChanged<LatLng>? onLongPress;
  const RouteMap({
    super.key,
    this.route,
    this.position,
    this.destination,
    this.onTap,
    this.online = false,
    this.heading = 0,
    this.followPosition = false,
    this.offlinePath,
    this.onLongPress,
  });
  @override
  State<RouteMap> createState() => _RouteMapState();
}

class _RouteMapState extends State<RouteMap> {
  final controller = MapController();
  bool follow = true;
  bool headingMode = false;
  bool rasterReady = false;
  MbTilesProvider? offline;
  @override
  void initState() {
    super.initState();
    if (widget.offlinePath != null) {
      offline = MbTilesProvider(widget.offlinePath!);
    }
  }

  @override
  void didUpdateWidget(covariant RouteMap old) {
    super.didUpdateWidget(old);
    if (widget.offlinePath != old.offlinePath) {
      offline = widget.offlinePath == null
          ? null
          : MbTilesProvider(widget.offlinePath!);
    }
    if (!rasterReady ||
        (Runtime.settings.value('mapEngine', 'vector') == 'vector' &&
            widget.offlinePath == null)) {
      return;
    }
    if (widget.followPosition && !old.followPosition) follow = true;
    if (old.destination != widget.destination && widget.destination != null) {
      follow = false;
      controller.move(widget.destination!, 15);
    }
    if (headingMode) controller.rotate(-widget.heading);
    if (widget.route != old.route &&
        widget.route != null &&
        widget.route!.points.length > 1) {
      controller.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(
            widget.route!.points.map((p) => p.coordinate).toList(),
          ),
          padding: const EdgeInsets.all(32),
        ),
      );
    }
    if (follow && widget.position != null && widget.position != old.position) {
      controller.move(widget.position!, controller.camera.zoom);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (Runtime.settings.value('mapEngine', 'vector') == 'vector' &&
        widget.offlinePath == null) {
      return VectorRouteMap(
        key: ValueKey(
          '${Runtime.settings.value('mapStyle', 'dark')}-${Runtime.settings.value('mapOffline', false)}-${Runtime.settings.value<Map<String, dynamic>?>('offlineView', null)?['id']}',
        ),
        route: widget.route,
        destination: widget.destination,
        onTap: widget.onTap,
        position: widget.position,
        heading: widget.heading,
        followPosition: widget.followPosition,
        onLongPress: widget.onLongPress,
      );
    }
    final points =
        widget.route?.points.map((p) => p.coordinate).toList() ?? <LatLng>[];
    final segments = <List<LatLng>>[];
    for (final point in widget.route?.points ?? <NavPoint>[]) {
      if (segments.isEmpty || point.breakBefore) segments.add([]);
      segments.last.add(point.coordinate);
    }
    return Stack(
      children: [
        FlutterMap(
          mapController: controller,
          options: MapOptions(
            onMapReady: () => rasterReady = true,
            initialCenter:
                widget.position ??
                (points.isEmpty ? const LatLng(0, 0) : points.first),
            initialZoom: points.isEmpty && widget.position == null ? 1 : 13,
            initialCameraFit: points.length > 1 && widget.position == null
                ? CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints(points),
                    padding: const EdgeInsets.all(32),
                  )
                : null,
            onPositionChanged: (_, gesture) {
              if (gesture) follow = false;
              if (mounted) setState(() {});
            },
            onTap: (_, point) => widget.onTap?.call(point),
            onLongPress: (_, point) => widget.onLongPress?.call(point),
          ),
          children: [
            if (widget.offlinePath != null)
              TileLayer(
                key: ValueKey(widget.offlinePath),
                tileProvider: offline!,
              )
            else if (widget.online)
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.bike_computer',
              ),
            if (points.isNotEmpty)
              PolylineLayer(
                polylines: [
                  for (final segment in segments)
                    Polyline(
                      points: segment,
                      color: const Color(0xff46b7ff),
                      strokeWidth: 6,
                    ),
                ],
              ),
            MarkerLayer(
              markers: [
                for (final p in widget.route?.waypoints ?? <NavPoint>[])
                  Marker(
                    point: p.coordinate,
                    child: const Icon(
                      Icons.place,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                if (points.isNotEmpty)
                  Marker(
                    point: points.first,
                    child: const Icon(
                      Icons.trip_origin,
                      color: Colors.green,
                      size: 28,
                    ),
                  ),
                if (points.isNotEmpty)
                  Marker(
                    point: points.last,
                    child: const Icon(
                      Icons.flag,
                      color: Colors.orange,
                      size: 32,
                    ),
                  ),
                if (widget.destination != null)
                  Marker(
                    point: widget.destination!,
                    child: const Icon(
                      Icons.place,
                      color: Colors.orange,
                      size: 36,
                    ),
                  ),
                if (widget.position != null)
                  Marker(
                    point: widget.position!,
                    child: const Icon(
                      Icons.navigation,
                      color: Colors.blue,
                      size: 36,
                    ),
                  ),
              ],
            ),
          ],
        ),
        Positioned(
          left: 8,
          bottom: 8,
          child: Container(
            color: Colors.black87,
            padding: const EdgeInsets.all(5),
            child: Text(
              widget.offlinePath != null
                  ? 'Offline MBTiles · bronlicentie van bestand'
                  : widget.online
                  ? '© OpenStreetMap contributors'
                  : 'Offline routespoor · geen achtergrondkaart',
              style: const TextStyle(fontSize: 10, color: Colors.white),
            ),
          ),
        ),
        Positioned(
          left: 8,
          top: 8,
          child: Container(
            color: Colors.black87,
            padding: const EdgeInsets.all(6),
            child: Text(
              '┠────────┨\n${_scale()} m',
              style: const TextStyle(fontSize: 11, color: Colors.white),
            ),
          ),
        ),
        Positioned(
          right: 8,
          top: 8,
          child: Column(
            children: [
              _button(
                Icons.add,
                () => controller.move(
                  controller.camera.center,
                  controller.camera.zoom + 1,
                ),
              ),
              _button(
                Icons.remove,
                () => controller.move(
                  controller.camera.center,
                  controller.camera.zoom - 1,
                ),
              ),
              _button(Icons.my_location, () {
                follow = true;
                if (widget.position != null) {
                  controller.move(widget.position!, 15);
                }
              }),
              _button(Icons.explore, () {
                headingMode = !headingMode;
                controller.rotate(headingMode ? -widget.heading : 0);
              }),
            ],
          ),
        ),
      ],
    );
  }

  int _scale() {
    try {
      return (156543.03392 *
              math.cos(controller.camera.center.latitude * math.pi / 180) /
              math.pow(2, controller.camera.zoom) *
              80)
          .round();
    } catch (_) {
      return 1000;
    }
  }

  Widget _button(IconData icon, VoidCallback action) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Material(
      color: Colors.black87,
      borderRadius: BorderRadius.circular(12),
      child: IconButton(
        color: Colors.white,
        onPressed: action,
        icon: Icon(icon),
      ),
    ),
  );
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}
