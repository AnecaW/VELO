import 'package:bike_computer/features/maps/map_settings_screen.dart';
import 'package:bike_computer/services/integrations/strava_integration.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:bike_computer/core/runtime.dart';
import 'package:bike_computer/core/platform_bridge.dart';
import 'package:bike_computer/services/navigation/gpx_route.dart';
import 'package:bike_computer/services/navigation/routing_client.dart';
import 'package:bike_computer/services/gps/gps_service.dart';
import 'package:bike_computer/models/gps_models.dart';
import 'package:bike_computer/widgets/route_map.dart';

class NavigationScreen extends StatefulWidget {
  const NavigationScreen({super.key});
  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  NavRoute? route;
  LatLng? position;
  RouteProgress? progress;
  String? error;
  bool busy = false, navigating = false, rerouting = false;
  final gps = RealGPSService();
  StreamSubscription<GPSLocation>? subscription;
  DateTime? lastReroute;
  int spoken = -1;
  double heading = 0;
  double speedMs = 0;
  final dest = TextEditingController();
  Timer? cacheTimer;
  String? cacheSource;
  @override
  void initState() {
    super.initState();
    Runtime.settings.addListener(_settingsChanged);
    _load();
    _watchLocation();
    cacheTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _checkCache(),
    );
  }

  void _settingsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      await StravaCache(Runtime.database).expire();
      cacheSource = await Runtime.database.getDocument('navigation', 'source');
      final raw = await Runtime.database.getDocument('navigation', 'selected');
      if (raw != null && mounted) setState(() => route = NavRoute.decode(raw));
    } catch (e) {
      _error(e);
    }
  }

  Future<void> _checkCache() async {
    if (cacheSource == null) return;
    await StravaCache(Runtime.database).expire();
    if (await Runtime.database.getDocument('routes', cacheSource!) == null &&
        mounted) {
      setState(() {
        route = null;
        progress = null;
        navigating = false;
        error = 'De tijdelijke Strava-route is verlopen of verwijderd. Synchroniseer opnieuw.';
      });
      cacheSource = null;
    }
  }

  void _error(Object e) {
    Runtime.lastError = e.toString();
    if (mounted) setState(() => error = e.toString());
  }

  Future<void> _store(NavRoute next, {String? sourceKey}) async {
    if (sourceKey == null) {
      await Runtime.database.putDocument('routes', next.name, next.encode());
    }
    cacheSource = sourceKey;
    if (sourceKey == null) {
      await Runtime.database.removeDocument('navigation', 'source');
    } else {
      await Runtime.database.putDocument('navigation', 'source', sourceKey);
    }
    await Runtime.database.putDocument('navigation', 'selected', next.encode());
    if (mounted) {
      setState(() {
        route = next;
        progress = null;
        error = null;
      });
    }
  }

  Future<void> _import() async {
    setState(() => busy = true);
    try {
      final files = await FilePicker.pickFiles(type: FileType.any);
      if (files.isEmpty) return;
      final length = await files.first.length();
      if (length == null || length > 10 * 1024 * 1024) {
        throw const FormatException('GPX maximaal 10 MB');
      }
      final source = utf8.decode(await files.first.readAsBytes());
      await _store(await compute(parseGpx, source));
    } catch (e) {
      _error(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _saved() async {
    try {
      await StravaCache(Runtime.database).expire();
      final routes = await Runtime.database.documents('routes');
      final origins = await Runtime.database.documents('route-source');
      final favorites = await Runtime.database.documents('favorites');
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        builder: (ctx) => ListView(
          children: [
            const ListTile(title: Text('Lokale routes · offline beschikbaar')),
            if (routes.isEmpty)
              const ListTile(title: Text('Importeer eerst een GPX-route')),
            for (final e in favorites.entries)
              ListTile(
                leading: const Icon(Icons.star),
                title: Text(e.key),
                onTap: () {
                  dest.text = e.value;
                  Navigator.pop(ctx);
                },
              ),
            for (final entry in routes.entries)
              ListTile(
                title: Text(NavRoute.decode(entry.value).name),
                subtitle: Text(
                  entry.key.startsWith('strava:')
                      ? 'Strava · tijdelijk offline beschikbaar · ${origins[entry.key] == null ? '' : jsonDecode(origins[entry.key]!)['synced']}'
                      : 'Lokaal · GPX / eigen route',
                ),
                leading: const Icon(Icons.route),
                onTap: () {
                  Navigator.pop(ctx);
                  _store(NavRoute.decode(entry.value), sourceKey: entry.key);
                },
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    await Runtime.database.removeDocument('routes', entry.key);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                ),
              ),
          ],
        ),
      );
    } catch (e) {
      _error(e);
    }
  }

  Future<void> _locate() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Schakel locatievoorzieningen in');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError('Locatietoestemming nodig voor navigatie');
    }
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        timeLimit: Duration(seconds: 20),
      ),
    );
    if (p.accuracy > 100) throw StateError('GPS nog onvoldoende nauwkeurig');
    if (mounted) setState(() => position = LatLng(p.latitude, p.longitude));
  }

  Future<void> _calculate() async {
    setState(() => busy = true);
    final client = RoutingClient();
    try {
      final key = await const FlutterSecureStorage().read(key: 'ors-key') ?? '';
      final parts = dest.text.split(',');
      NavPoint? destination;
      if (parts.length == 2 &&
          parts.every((s) => double.tryParse(s.trim()) != null)) {
        final lat = double.parse(parts[0].trim()),
            lon = double.parse(parts[1].trim());
        if (!lat.isFinite ||
            !lon.isFinite ||
            lat.abs() > 90 ||
            lon.abs() > 180) {
          throw const FormatException('Ongeldige coördinaten');
        }
        destination = NavPoint(lat, lon);
      } else {
        final results = await client.search(dest.text, key);
        if (results.isEmpty) throw StateError('Geen adres gevonden');
        if (!mounted) return;
        destination = await showModalBottomSheet<NavPoint>(
          context: context,
          builder: (ctx) => ListView(
            children: [
              const ListTile(title: Text('Kies je bestemming')),
              for (final r in results)
                ListTile(
                  title: Text(r.label),
                  onTap: () => Navigator.pop(ctx, r.point),
                ),
            ],
          ),
        );
        if (destination == null) return;
      }
      await _locate();
      final result = await client.route(
        NavPoint(position!.latitude, position!.longitude),
        destination,
        key,
        profile: Runtime.settings.value('routingProfile', 'cycling-regular'),
      );
      await _store(result);
    } catch (e) {
      _error(e);
    } finally {
      client.dispose();
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _watchLocation() async {
    try {
      subscription ??= gps.locationStream.listen((p) {
        if (!mounted || p.accuracy > 100) return;
        setState(() {
          position = LatLng(p.latitude, p.longitude);
          heading = p.heading;
          speedMs = p.speed;
        });
        if (navigating && route != null) {
          setState(
            () => progress = RouteProgress.locate(
              route!,
              NavPoint(p.latitude, p.longitude),
              accuracy: p.accuracy,
            ),
          );
        }
      }, onError: (Object e) => _error(e));
      await gps.startListening();
    } catch (e) {
      _error(e);
    }
  }

  Future<void> _navigate() async {
    try {
      if (navigating) {
        await gps.stopListening();
        await subscription?.cancel();
        subscription = null;
        if (mounted) setState(() => navigating = false);
        await _watchLocation();
        return;
      }
      await subscription?.cancel();
      subscription = gps.locationStream.listen((p) {
        if (route == null || !mounted || p.accuracy > 100) return;
        final next = RouteProgress.locate(
          route!,
          NavPoint(p.latitude, p.longitude),
          accuracy: p.accuracy,
          threshold: Runtime.settings.value('offRoute', 40.0),
        );
        setState(() {
          position = LatLng(p.latitude, p.longitude);
          heading = p.heading;
          speedMs = p.speed;
          progress = next;
        });
        final upcoming = route!.steps
            .where((s) => s.index >= next.segment)
            .firstOrNull;
        if (upcoming != null &&
            route!.metersTo(upcoming.index) - next.traveled < 100 &&
            upcoming.index != spoken &&
            Runtime.settings.value('voice', false)) {
          spoken = upcoming.index;
          PlatformBridge.call(
            'speak',
            upcoming.instruction,
          ).catchError((_) => null);
        }
        if (next.offRoute &&
            Runtime.settings.value('reroute', false) &&
            !rerouting &&
            (lastReroute == null ||
                DateTime.now().difference(lastReroute!).inSeconds > 60)) {
          _reroute(p);
        }
      }, onError: (Object e) => _error(e));
      await gps.startListening();
      if (mounted) setState(() => navigating = true);
    } catch (e) {
      await subscription?.cancel();
      subscription = null;
      _error(e);
    }
  }

  Future<void> _reroute(GPSLocation p) async {
    if (cacheSource?.startsWith('strava:') == true) {
      _error(
        StateError(
          'Automatische herberekening van een Strava-route is uitgeschakeld: routegegevens worden niet naar andere diensten doorgestuurd.',
        ),
      );
      return;
    }
    rerouting = true;
    lastReroute = DateTime.now();
    final client = RoutingClient();
    try {
      final key = await const FlutterSecureStorage().read(key: 'ors-key') ?? '';
      final next = await client.route(
        NavPoint(p.latitude, p.longitude),
        route!.points.last,
        key,
        profile: Runtime.settings.value('routingProfile', 'cycling-regular'),
      );
      await _store(next);
    } catch (e) {
      _error(e);
    } finally {
      client.dispose();
      rerouting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final upcoming = progress == null
        ? null
        : route?.steps.where((s) => s.index >= progress!.segment).firstOrNull;
    final nextMeters = upcoming == null
        ? null
        : (route!.metersTo(upcoming.index) - progress!.traveled)
              .clamp(0, double.infinity)
              .round();
    final eta = progress != null && speedMs > 1
        ? TimeOfDay.fromDateTime(
            DateTime.now().add(
              Duration(seconds: (progress!.remaining / speedMs).round()),
            ),
          ).format(context)
        : null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kaart'),
        actions: [
          IconButton(
            tooltip: 'Lokale routes',
            onPressed: _saved,
            icon: const Icon(Icons.folder_open_outlined),
          ),
          IconButton(
            tooltip: 'GPX importeren',
            onPressed: busy ? null : _import,
            icon: const Icon(Icons.file_open_outlined),
          ),
          IconButton(
            tooltip: 'Kaartinstellingen',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const MapSettingsScreen(),
              ),
            ),
            icon: const Icon(Icons.layers_outlined),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: RouteMap(
              route: route,
              position: position,
              heading: heading,
              online: Runtime.settings.value('onlineMap', false),
              offlinePath:
                  Runtime.settings.value('mapEngine', 'vector') == 'raster'
                  ? Runtime.settings.value<String?>('offlineMap', null)
                  : null,
              onLongPress: (p) {
                dest.text =
                    '${p.latitude.toStringAsFixed(6)}, ${p.longitude.toStringAsFixed(6)}';
                _planning();
              },
            ),
          ),
          if (busy)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(),
            ),
          if (navigating && progress != null)
            Positioned(
              top: 12,
              left: 12,
              right: 76,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        progress!.offRoute
                            ? 'Van de route afgeweken'
                            : upcoming?.instruction ?? 'Volg het GPX-spoor',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '${nextMeters == null ? '' : 'Volgende afslag $nextMeters m · '}${(progress!.remaining / 1000).toStringAsFixed(1)} km resterend',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 22,
            child: Card(
              color: Theme.of(context).colorScheme.surface
                  .withValues(alpha: .95),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (error != null)
                      Text(
                        error!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.orange),
                      ),
                    if (route != null)
                      Text(
                        route!.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    if (navigating)
                      Text(
                        '${(progress?.remaining ?? route?.meters ?? 0) / 1000} km · ${speedMs > 0 ? (speedMs * 3.6).toStringAsFixed(1) : '—'} km/h${eta == null ? '' : ' · ETA ~$eta'}',
                      ),
                    if (route != null && route!.steps.isEmpty)
                      const Text(
                        'GPX-spoor zonder afslagdata',
                        style: TextStyle(fontSize: 11),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: busy ? null : _planning,
                            icon: const Icon(Icons.search),
                            label: const Text('Bestemming'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (route != null)
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _navigate,
                              child: Text(
                                navigating ? 'Stop navigatie' : 'Volg route',
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _planning() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.viewInsetsOf(ctx).bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: dest,
              decoration: const InputDecoration(
                labelText: 'Adres, plaats of latitude, longitude',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _calculate();
              },
              child: const Text('Echte fietsroute berekenen'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _import();
              },
              child: const Text('GPX importeren (ook offline)'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    cacheTimer?.cancel();
    Runtime.settings.removeListener(_settingsChanged);
    subscription?.cancel();
    gps.dispose();
    dest.dispose();
    super.dispose();
  }
}
