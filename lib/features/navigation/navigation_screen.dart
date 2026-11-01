import '../../models/ride_session.dart';
import '../../services/gps/gps_service.dart';
import '../../services/navigation/map_provider.dart';
import '../../models/bike_type.dart';
import '../../widgets/bike_type_selector.dart';
import '../../services/navigation/geocoding_service.dart';
import '../../services/navigation/brouter_service.dart';
import '../../services/navigation/navigation_service.dart';

import 'package:bike_computer/features/maps/map_settings_screen.dart';
import 'package:bike_computer/services/integrations/strava_integration.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../../services/navigation/offline_maps.dart';

import 'package:bike_computer/core/runtime.dart';
import 'package:bike_computer/core/platform_bridge.dart';
import 'package:bike_computer/services/navigation/gpx_route.dart';
import 'package:bike_computer/models/gps_models.dart';
import 'package:bike_computer/widgets/route_map.dart';

class NavigationScreen extends StatefulWidget {
  final GeocodingService? geocoder;
  final CyclingRouter? router;
  final GPSService? gps;
  final Future<GPSLocation> Function()? locate;
  final bool platformServices;
  const NavigationScreen({
    super.key,
    this.geocoder,
    this.router,
    this.gps,
    this.locate,
    this.platformServices = true,
  });
  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen>
    with WidgetsBindingObserver {
  bool _mapVisible = false, _foreground = true, offline = false;
  StreamSubscription<List<ConnectivityResult>>? connectivity;
  Future<void> _locationTask = Future.value();
  NavRoute? route;
  LatLng? position;
  RouteProgress? progress;
  String? error;
  bool busy = false, navigating = false, rerouting = false;
  late final GPSService gps;
  late final GeocodingService geocoder;
  late final CyclingRouter router;
  final deviation = OffRouteDetector();
  AddressResult? destination;
  List<AddressResult> suggestions = [];
  Timer? searchDebounce;
  int searchGeneration = 0, destinationGeneration = 0;
  bool searching = false, searched = false, searchCache = false;
  String? searchError;
  final alternatives = <NavRoute>[];
  int selectedAlternative = 0;
  BikeType get bike {
    final s = Runtime.ride.session;
    if (s.startTime != null &&
        ![RideState.saved, RideState.idle, RideState.ready].contains(s.state)) {
      return s.bikeType;
    }
    return BikeType.parse(Runtime.settings.value<String?>('bikeType', null));
  }

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
    gps = widget.gps ?? Runtime.location.lease();
    geocoder = widget.geocoder ?? PhotonGeocoder(Runtime.database);
    router = widget.router ?? BRouterService();
    Runtime.settings.addListener(_settingsChanged);
    _load();
    if (widget.platformServices) {
      Connectivity()
          .checkConnectivity()
          .then(_network)
          .catchError((Object _) {});
      connectivity = Connectivity().onConnectivityChanged.listen(
        _network,
        onError: (Object _) {},
      );
      OfflineMaps.instance.addListener(_settingsChanged);
      OfflineMaps.instance.load().catchError((Object _) {});
    }
    WidgetsBinding.instance.addObserver(this);
    cacheTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _checkCache(),
    );
  }

  void _network(List<ConnectivityResult> results) {
    if (mounted) {
      setState(() => offline = results.contains(ConnectivityResult.none));
    }
  }

  String get offlineDescription {
    final p = position;
    final maps = OfflineMaps.instance;
    final style = Runtime.settings.value('mapStyle', 'dark');
    final url = MapStyleSpec.builtins
        .where((s) => s.id == style)
        .firstOrNull
        ?.url;
    final complete =
        p != null &&
        maps.regions.any(
          (r) =>
              maps.statuses[r.id]?.isComplete == true &&
              r.definition.mapStyleUrl == url &&
              p.latitude >= r.definition.bounds.southwest.latitude &&
              p.latitude <= r.definition.bounds.northeast.latitude &&
              p.longitude >= r.definition.bounds.southwest.longitude &&
              p.longitude <= r.definition.bounds.northeast.longitude,
        );
    return '${offline ? 'Offline · ' : ''}${complete ? 'Offline kaartgebied beschikbaar op je positie' : 'Geen offline kaartgebied op deze positie · alleen eventueel gecachete tegels'}${route == null ? '' : ' · routespoor lokaal bewaard'}';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible != _mapVisible) {
      _mapVisible = visible;
      _updateLocation();
    }
  }

  @override
  void didChangeMetrics() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _updateLocation();
  }

  void _updateLocation() {
    _locationTask = _locationTask
        .then((_) async {
          if (!mounted) return;
          if ((_mapVisible && _foreground) || navigating) {
            await _watchLocation();
          } else {
            await gps.stopListening();
          }
        })
        .catchError((Object _) {});
  }

  void _settingsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      await StravaCache(Runtime.database).expire();
      cacheSource = await Runtime.database.getDocument('navigation', 'source');
      final raw = await Runtime.database.getDocument('navigation', 'selected');
      final selected = await Runtime.database.getDocument(
        'navigation',
        'destination',
      );
      if (raw != null && mounted) setState(() => route = NavRoute.decode(raw));
      if (selected != null && mounted) {
        setState(
          () => destination = AddressResult.fromJson(jsonDecode(selected)),
        );
      }
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
      _updateLocation();
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
    deviation.reset();
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
      final imported = await compute(parseGpx, source);
      if (navigating) await _navigate();
      await _clearDestination();
      await _store(imported);
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
                  try {
                    dest.text = jsonDecode(e.value)['value'] as String;
                  } catch (_) {
                    dest.text = e.value;
                  }
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
                  () async {
                    if (navigating) await _navigate();
                    await _clearDestination();
                    await _store(
                      NavRoute.decode(entry.value),
                      sourceKey: entry.key,
                    );
                  }();
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

  Future<void> _clearDestination() async {
    destinationGeneration++;
    await Runtime.database.removeDocument('navigation', 'destination');
    if (mounted) {
      setState(() {
        destination = null;
        dest.clear();
        alternatives.clear();
        progress = null;
      });
    }
  }

  Future<void> _locate() async {
    if (widget.locate != null) {
      final p = await widget.locate!();
      if (mounted) setState(() => position = LatLng(p.latitude, p.longitude));
      return;
    }
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

  void _search(String text) {
    searchDebounce?.cancel();
    final generation = ++searchGeneration;
    setState(() {
      suggestions = [];
      searchError = null;
      searched = false;
      searching = text.trim().length >= 3;
    });
    if (text.trim().length < 3) return;
    searchDebounce = Timer(const Duration(milliseconds: 600), () async {
      try {
        final results = await geocoder.search(
          text,
          focus: position == null
              ? null
              : NavPoint(position!.latitude, position!.longitude),
        );
        if (!mounted || generation != searchGeneration) return;
        setState(() {
          suggestions = results;
          searching = false;
          searched = true;
          searchCache =
              geocoder is PhotonGeocoder && (geocoder as PhotonGeocoder).cached;
        });
      } catch (_) {
        if (mounted && generation == searchGeneration) {
          setState(() {
            searching = false;
            searchError = 'Geen verbinding met de adresdienst. Probeer opnieuw; opgeslagen routes blijven beschikbaar.';
          });
        }
      }
    });
  }

  Future<void> _select(AddressResult selected) async {
    searchDebounce?.cancel();
    searchGeneration++;
    cacheSource = null;
    destinationGeneration++;
    FocusManager.instance.primaryFocus?.unfocus();
    if (navigating) await _navigate();
    if (!mounted) return;
    setState(() {
      destination = selected;
      dest.text = selected.title;
      suggestions = [];
      searching = false;
      searched = false;
      searchError = null;
      route = null;
      progress = null;
      alternatives.clear();
      error = null;
    });
    await Runtime.database.removeDocument('navigation', 'selected');
    await Runtime.database.removeDocument('navigation', 'source');
    await Runtime.database.putDocument(
      'navigation',
      'destination',
      jsonEncode(selected.toJson()),
    );
  }

  Future<void> _pick(LatLng point) async {
    await _select(
      AddressResult(
        'Gekozen locatie',
        '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}',
        NavPoint(point.latitude, point.longitude),
      ),
    );
    final generation = destinationGeneration;
    try {
      final address = await geocoder.reverse(
        NavPoint(point.latitude, point.longitude),
      );
      if (address != null && mounted && generation == destinationGeneration) {
        setState(() {
          destination = AddressResult(
            address.title,
            address.subtitle,
            NavPoint(point.latitude, point.longitude),
          );
          dest.text = address.title;
        });
        await Runtime.database.putDocument(
          'navigation',
          'destination',
          jsonEncode(destination!.toJson()),
        );
      }
    } catch (_) {
      if (mounted && generation == destinationGeneration) {
        setState(
          () => error = 'Adres niet beschikbaar; je kunt naar deze kaartpositie navigeren.',
        );
      }
    }
  }

  Future<void> _calculate({bool alternative = false}) async {
    if (destination == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    final target = destination!;
    final generation = destinationGeneration;
    final selectedBike = bike;
    try {
      await _locate();
      final result = await router.calculate(
        NavPoint(position!.latitude, position!.longitude),
        target.point,
        selectedBike,
        alternative: alternative ? alternatives.length.clamp(1, 2) : 0,
      );
      if (!mounted || generation != destinationGeneration) return;
      if (!alternative) alternatives.clear();
      if (alternatives.any(
        (r) =>
            r.points.length == result.points.length &&
            r.points.asMap().entries.every(
              (e) =>
                  e.value.lat == result.points[e.key].lat &&
                  e.value.lon == result.points[e.key].lon,
            ),
      )) {
        setState(() => error = 'De router levert hier geen ander alternatief.');
        return;
      }
      alternatives.add(result);
      selectedAlternative = alternatives.length - 1;
      await _store(result);
    } catch (e) {
      _error(e);
    } finally {
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
        if (_mapVisible && _foreground) await _watchLocation();
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
        final shouldReroute = deviation.shouldRecalculate(
          next,
          p.accuracy,
          DateTime.now(),
        );
        if (shouldReroute &&
            Runtime.settings.value('reroute', true) &&
            !rerouting &&
            (lastReroute == null ||
                DateTime.now().difference(lastReroute!).inSeconds > 60)) {
          _reroute(p);
        }
      }, onError: (Object e) => _error(e));
      try {
        await PlatformBridge.call('notifications');
      } catch (_) {}
      await gps.startListening();
      spoken = -1;
      deviation.reset();
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
    setState(() => rerouting = true);
    final original = route;
    lastReroute = DateTime.now();

    try {
      final next = await router.calculate(
        NavPoint(p.latitude, p.longitude),
        route!.points.last,
        BikeType.parse(route!.bikeType ?? bike.name),
      );
      if (mounted && navigating && identical(route, original)) {
        await _store(next);
      }
    } catch (e) {
      _error(e);
    } finally {
      if (mounted) setState(() => rerouting = false);
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
    final remaining = progress?.remaining ?? route?.meters;
    final seconds = route?.durationSeconds == null || route!.meters <= 0
        ? null
        : route!.durationSeconds! * (remaining ?? 0) / route!.meters;
    final eta = seconds == null
        ? null
        : TimeOfDay.fromDateTime(
            DateTime.now().add(Duration(seconds: seconds.round())),
          ).format(context);
    final target = destination?.point ?? route?.points.last;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Kaart'),
        actions: [
          IconButton(
            tooltip: 'Lokale routes',
            onPressed: busy ? null : _saved,
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
      body: Column(
        children: [
          if (!navigating)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Column(
                children: [
                  TextField(
                    controller: dest,
                    enabled: !busy,
                    onChanged: _search,
                    decoration: InputDecoration(
                      hintText: 'Zoek een adres, plaats of bestemming...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: searching
                          ? const Padding(
                              padding: EdgeInsets.all(14),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : IconButton(
                              tooltip: 'Zoekveld wissen',
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                dest.clear();
                                _search('');
                              },
                            ),
                    ),
                  ),
                  if (searchError != null)
                    ListTile(
                      dense: true,
                      title: Text(searchError!),
                      trailing: IconButton(
                        tooltip: 'Opnieuw zoeken',
                        onPressed: () => _search(dest.text),
                        icon: const Icon(Icons.refresh),
                      ),
                    ),
                  if (searched && suggestions.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(10),
                      child: Text(
                        'Geen adressen gevonden. Probeer een straat, plaats of postcode.',
                      ),
                    ),
                  if (suggestions.isNotEmpty)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          if (searchCache)
                            const Padding(
                              padding: EdgeInsets.all(4),
                              child: Text(
                                'Recent zoekresultaat · lokaal bewaard',
                                style: TextStyle(fontSize: 11),
                              ),
                            ),
                          for (final r in suggestions)
                            ListTile(
                              dense: true,
                              leading: const Icon(Icons.place_outlined),
                              title: Text(r.title),
                              subtitle: Text(
                                r.subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => _select(r),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: RouteMap(
                    route: route,
                    position: position,
                    heading: heading,
                    destination: destination?.point.coordinate,
                    followPosition: navigating,
                    online: Runtime.settings.value('onlineMap', false),
                    offlinePath:
                        Runtime.settings.value('mapEngine', 'vector') ==
                            'raster'
                        ? Runtime.settings.value<String?>('offlineMap', null)
                        : null,
                    onLongPress: busy ? null : _pick,
                    onTap: busy || navigating ? null : _pick,
                  ),
                ),
                if (busy || rerouting)
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: LinearProgressIndicator(),
                  ),
                if (navigating)
                  Positioned(
                    top: 12,
                    left: 12,
                    right: 76,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              progress?.offRoute == true
                                  ? (rerouting
                                        ? 'Route herberekenen…'
                                        : 'Van de route afgeweken')
                                  : upcoming?.instruction ??
                                        'Volg het routespoor',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            if (nextMeters != null)
                              Text(
                                'Over $nextMeters m',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (View.of(context).viewInsets.bottom == 0 || navigating)
            Material(
              color: Theme.of(context).colorScheme.surface,
              child: SafeArea(
                top: false,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * .38,
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (error != null)
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  error!,
                                  maxLines: 3,
                                  style: const TextStyle(color: Colors.orange),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Melding sluiten',
                                icon: const Icon(Icons.close),
                                onPressed: () => setState(() => error = null),
                              ),
                            ],
                          ),
                        if (!navigating)
                          Row(
                            children: [
                              Expanded(
                                child: BikeTypeSelector(
                                  fixed:
                                      Runtime.ride.session.startTime != null &&
                                          ![
                                            RideState.saved,
                                            RideState.idle,
                                            RideState.ready,
                                          ].contains(Runtime.ride.session.state)
                                      ? Runtime.ride.session.bikeType
                                      : null,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Huidige locatie als vertrekpunt',
                                icon: const Icon(Icons.my_location),
                                onPressed: () async {
                                  try {
                                    await _locate();
                                  } catch (e) {
                                    _error(e);
                                  }
                                },
                              ),
                            ],
                          ),
                        if (destination != null)
                          Text(
                            destination!.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        if (route != null) ...[
                          Text(
                            '${((remaining ?? 0) / 1000).toStringAsFixed(1)} km${seconds == null ? '' : ' · ~${(seconds / 60).ceil()} min'}${navigating && eta != null ? ' · aankomst ~$eta' : ''}${!navigating && route!.ascent != null ? ' · ↗ ${route!.ascent!.round()} m' : ''}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (!navigating)
                            Text(
                              'Van ${route!.points.first.lat.toStringAsFixed(4)}, ${route!.points.first.lon.toStringAsFixed(4)} · ${route!.name}',
                              style: const TextStyle(fontSize: 11),
                            ),
                          if (navigating && position != null && target != null)
                            Text(
                              '${(NavRoute.distance(NavPoint(position!.latitude, position!.longitude), target) / 1000).toStringAsFixed(1)} km hemelsbreed tot bestemming',
                              style: const TextStyle(fontSize: 11),
                            ),
                          if (route!.steps.isEmpty)
                            const Text(
                              'Routespoor zonder betrouwbare afslagdata',
                              style: TextStyle(fontSize: 11),
                            ),
                          if (!navigating && alternatives.length > 1)
                            Wrap(
                              spacing: 8,
                              children: [
                                for (var i = 0; i < alternatives.length; i++)
                                  ChoiceChip(
                                    label: Text(
                                      i == 0
                                          ? 'Voorkeursroute'
                                          : 'Alternatief $i',
                                    ),
                                    selected: selectedAlternative == i,
                                    onSelected: busy
                                        ? null
                                        : (_) {
                                            setState(
                                              () => selectedAlternative = i,
                                            );
                                            _store(alternatives[i]);
                                          },
                                  ),
                              ],
                            ),
                        ],
                        if (destination == null && route == null)
                          const Text(
                            'Zoek een bestemming of tik op de kaart.',
                            style: TextStyle(fontSize: 12),
                          ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            if (!navigating && destination != null)
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: busy ? null : () => _calculate(),
                                  icon: const Icon(Icons.alt_route),
                                  label: const Text('Bereken route'),
                                ),
                              ),
                            if (!navigating &&
                                destination != null &&
                                route != null)
                              const SizedBox(width: 8),
                            if (route != null)
                              Expanded(child: _navigationButton()),
                          ],
                        ),
                        if (!navigating && target != null)
                          Row(
                            children: [
                              if (route != null &&
                                  destination != null &&
                                  alternatives.length < 3)
                                Expanded(
                                  child: TextButton(
                                    onPressed: busy
                                        ? null
                                        : () => _calculate(alternative: true),
                                    child: const Text('Ander alternatief'),
                                  ),
                                ),
                              Expanded(
                                child: TextButton.icon(
                                  onPressed: () async {
                                    try {
                                      await ExternalNavigation.open(target);
                                    } catch (e) {
                                      _error(e);
                                    }
                                  },
                                  icon: const Icon(Icons.open_in_new, size: 16),
                                  label: const Text('Google Maps'),
                                ),
                              ),
                            ],
                          ),
                        if (navigating)
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Automatisch herberekenen',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                              Switch(
                                value: Runtime.settings.value('reroute', true),
                                onChanged: (v) =>
                                    Runtime.settings.set('reroute', v),
                              ),
                            ],
                          ),
                        Text(
                          offlineDescription,
                          style: const TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _navigationButton() => OutlinedButton.icon(
    onPressed: busy ? null : _navigate,
    icon: Icon(navigating ? Icons.stop : Icons.navigation),
    label: Text(navigating ? 'Stop navigatie' : 'Navigeren in VELO'),
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    connectivity?.cancel();
    OfflineMaps.instance.removeListener(_settingsChanged);
    cacheTimer?.cancel();
    Runtime.settings.removeListener(_settingsChanged);
    subscription?.cancel();
    gps.stopListening();
    searchDebounce?.cancel();
    geocoder.dispose();
    router.dispose();
    dest.dispose();
    super.dispose();
  }
}
