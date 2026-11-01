import 'dart:io';

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:latlong2/latlong.dart';
import 'package:bike_computer/core/runtime.dart';
import 'package:bike_computer/services/navigation/gpx_route.dart';
import 'package:bike_computer/services/navigation/map_provider.dart';

class VectorRouteMap extends StatefulWidget {
  final NavRoute? route;
  final LatLng? position;
  final double heading;
  final ValueChanged<LatLng>? onLongPress;
  const VectorRouteMap({
    super.key,
    this.route,
    this.position,
    this.heading = 0,
    this.onLongPress,
  });
  @override
  State<VectorRouteMap> createState() => _VectorRouteMapState();
}

class _VectorRouteMapState extends State<VectorRouteMap> {
  ml.MapLibreMapController? controller;
  bool ready = false,
      follow = true,
      bearing = false,
      drawing = false,
      pending = false;
  String? error;
  ml.Circle? location;
  String? style;
  String get selected {
    final id = Runtime.settings.value('mapStyle', 'dark');
    return id == 'custom'
        ? Runtime.settings.value('customStyle', '')
        : MapStyleSpec.builtins
              .firstWhere(
                (s) => s.id == id,
                orElse: () => MapStyleSpec.builtins.first,
              )
              .url;
  }

  @override
  void initState() {
    super.initState();
    if (!Platform.isAndroid && !Platform.isIOS) return;
    configureMapNetworking()
        .then((_) => ml.setOffline(Runtime.settings.value('mapOffline', false)))
        .catchError((Object e) {
          if (mounted) setState(() => error = e.toString());
        });
  }

  @override
  void didUpdateWidget(covariant VectorRouteMap old) {
    super.didUpdateWidget(old);
    if (old.route != widget.route) _draw();
    if (old.position != widget.position) _position();
  }

  Future<void> _draw() async {
    if (!ready || controller == null) return;
    if (drawing) {
      pending = true;
      return;
    }
    drawing = true;
    try {
      await controller!.clearLines();
      await controller!.clearCircles();
      location = null;
      final segments = <List<ml.LatLng>>[];
      for (final p in widget.route?.points ?? <NavPoint>[]) {
        if (segments.isEmpty || p.breakBefore) segments.add([]);
        segments.last.add(ml.LatLng(p.lat, p.lon));
      }
      for (final points in segments) {
        if (points.length > 1) {
          await controller!.addLine(
            ml.LineOptions(
              geometry: points,
              lineColor: '#7CDEC2',
              lineWidth: 5,
            ),
          );
        }
      }
      final points = widget.route?.points;
      if (points != null && points.isNotEmpty) {
        await controller!.addCircle(
          ml.CircleOptions(
            geometry: ml.LatLng(points.first.lat, points.first.lon),
            circleColor: '#7cdec2',
            circleRadius: 7,
            circleStrokeWidth: 2,
            circleStrokeColor: '#000000',
          ),
        );
        await controller!.addCircle(
          ml.CircleOptions(
            geometry: ml.LatLng(points.last.lat, points.last.lon),
            circleColor: '#ffb454',
            circleRadius: 8,
          ),
        );
        for (final p in widget.route!.waypoints) {
          await controller!.addCircle(
            ml.CircleOptions(
              geometry: ml.LatLng(p.lat, p.lon),
              circleColor: '#ffffff',
              circleRadius: 4,
            ),
          );
        }
        if (widget.position == null) {
          await controller!.animateCamera(
            ml.CameraUpdate.newLatLngBounds(
              ml.LatLngBounds(
                southwest: ml.LatLng(
                  points.map((p) => p.lat).reduce((a, b) => a < b ? a : b),
                  points.map((p) => p.lon).reduce((a, b) => a < b ? a : b),
                ),
                northeast: ml.LatLng(
                  points.map((p) => p.lat).reduce((a, b) => a > b ? a : b),
                  points.map((p) => p.lon).reduce((a, b) => a > b ? a : b),
                ),
              ),
              left: 40,
              right: 40,
              top: 40,
              bottom: 40,
            ),
          );
        }
      }
      await _position();
    } catch (e) {
      if (mounted) setState(() => error = 'Kaartlaag: $e');
    } finally {
      drawing = false;
      if (pending) {
        pending = false;
        _draw();
      }
    }
  }

  Future<void> _position() async {
    if (!ready || controller == null || widget.position == null) return;
    try {
      final p = ml.LatLng(
        widget.position!.latitude,
        widget.position!.longitude,
      );
      if (location == null) {
        location = await controller!.addCircle(
          ml.CircleOptions(
            geometry: p,
            circleRadius: 8,
            circleColor: '#53b9ff',
            circleStrokeColor: '#ffffff',
            circleStrokeWidth: 3,
          ),
        );
      } else {
        await controller!.updateCircle(
          location!,
          ml.CircleOptions(geometry: p),
        );
      }
      if (follow) {
        await controller!.animateCamera(
          ml.CameraUpdate.newCameraPosition(
            ml.CameraPosition(
              target: p,
              zoom: controller!.cameraPosition?.zoom == 1
                  ? 15
                  : controller!.cameraPosition?.zoom ?? 15,
              bearing: bearing ? widget.heading : 0,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = 'Positie tonen: $e');
    }
  }

  ml.CameraPosition _initialCamera() {
    final view = Runtime.settings.value<Map<String, dynamic>?>(
      'offlineView',
      null,
    );
    if (Runtime.settings.value('mapOffline', false) && view != null) {
      follow = false;
      return ml.CameraPosition(
        target: ml.LatLng(
          (view['lat'] as num).toDouble(),
          (view['lon'] as num).toDouble(),
        ),
        zoom: (view['zoom'] as num).toDouble(),
      );
    }
    return ml.CameraPosition(
      target: widget.position == null
          ? const ml.LatLng(0, 0)
          : ml.LatLng(widget.position!.latitude, widget.position!.longitude),
      zoom: widget.position == null ? 1 : 15,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return const Center(
        child: Text('MapLibre-kaarten vereisen Android of iOS'),
      );
    }
    final url = selected;
    if (url.isEmpty) {
      return const Center(
        child: Text('Configureer eerst een geldige kaartstijl.'),
      );
    }
    return Stack(
      children: [
        Listener(
          onPointerDown: (_) => follow = false,
          child: ml.MapLibreMap(
            key: ValueKey(url),
            styleString: url,
            initialCameraPosition: _initialCamera(),
            trackCameraPosition: true,
            scaleControlEnabled: true,
            compassEnabled: true,
            onMapCreated: (c) {
              controller = c;
              ready = false;
              location = null;
            },
            onStyleLoadedCallback: () {
              if (mounted) {
                setState(() {
                  ready = true;
                  error = null;
                });
                _draw();
              }
            },
            onMapLongClick: (_, p) =>
                widget.onLongPress?.call(LatLng(p.latitude, p.longitude)),
            onCameraTrackingDismissed: () => follow = false,
            onCameraMove: (_) {},
          ),
        ),
        if (!ready)
          const Positioned(
            top: 12,
            left: 12,
            child: Chip(label: Text('Kaartgegevens laden…')),
          ),
        if (widget.position == null)
          const Positioned(
            top: 52,
            left: 12,
            child: Chip(label: Text('Geen actuele GPS-positie')),
          ),
        if (error != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 30,
            child: Material(
              color: Colors.black87,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  error!,
                  style: const TextStyle(color: Colors.orange),
                ),
              ),
            ),
          ),
        Positioned(
          right: 12,
          top: 16,
          child: Column(
            children: [
              _button(
                'Inzoomen',
                Icons.add,
                () => controller?.animateCamera(ml.CameraUpdate.zoomIn()),
              ),
              _button(
                'Uitzoomen',
                Icons.remove,
                () => controller?.animateCamera(ml.CameraUpdate.zoomOut()),
              ),
              _button('Positie volgen', Icons.my_location, () {
                if (widget.position == null) {
                  setState(
                    () => error = 'Nog geen actuele GPS-positie beschikbaar',
                  );
                  return;
                }
                follow = true;
                _position();
              }),
              _button('Kaartoriëntatie', Icons.explore_outlined, () {
                bearing = !bearing;
                _position();
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _button(String label, IconData icon, VoidCallback action) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: .94),
      borderRadius: BorderRadius.circular(16),
      child: IconButton(tooltip: label, onPressed: action, icon: Icon(icon)),
    ),
  );
  @override
  void dispose() {
    // MapLibreMap owns and disposes its native controller.
    ready = false;
    controller = null;
    super.dispose();
  }
}
