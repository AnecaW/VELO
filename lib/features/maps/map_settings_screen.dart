import 'package:bike_computer/core/platform_bridge.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:bike_computer/core/runtime.dart';
import 'package:bike_computer/services/navigation/map_provider.dart';
import 'package:bike_computer/services/navigation/offline_maps.dart';
import 'package:bike_computer/services/navigation/gpx_route.dart';
import 'package:bike_computer/services/navigation/routing_client.dart';
import 'package:bike_computer/widgets/vector_route_map.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:latlong2/latlong.dart';

class MapSettingsScreen extends StatefulWidget {
  const MapSettingsScreen({super.key});
  @override
  State<MapSettingsScreen> createState() => _MapSettingsScreenState();
}

class _MapSettingsScreenState extends State<MapSettingsScreen> {
  final url = TextEditingController();
  String? error;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Kaartbronnen & stijlen')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'MapLibre Native · echte vectorkaarten',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        const Text(
          'Kaartstijl bepaalt de weergave; OpenFreeMap levert OpenStreetMap-geografie. Online laden deelt het bekeken gebied met de provider.',
        ),
        for (final style in MapStyleSpec.builtins)
          Card(
            child: ListTile(
              title: Text(style.name),
              subtitle: Text(
                '${style.provider} · vector\nInternet voor nieuwe gebieden · offline download ondersteund',
              ),
              isThreeLine: true,
              trailing: Icon(
                Runtime.settings.value('mapStyle', 'dark') == style.id
                    ? Icons.check_circle
                    : Icons.circle_outlined,
              ),
              onTap: () async {
                await Runtime.settings.set('mapStyle', style.id);
                await Runtime.settings.set('mapEngine', 'vector');
                if (mounted) setState(() {});
              },
            ),
          ),
        TextField(
          controller: url,
          decoration: const InputDecoration(
            labelText: 'Eigen MapLibre style.json URL · HTTPS',
          ),
        ),
        OutlinedButton(
          onPressed: () async {
            final uri = Uri.tryParse(url.text.trim());
            if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
              setState(() => error = 'Voer een geldige HTTPS-stijl in');
              return;
            }
            await Runtime.settings.set('customStyle', uri.toString());
            await Runtime.settings.set('mapStyle', 'custom');
            await Runtime.settings.set('mapEngine', 'vector');
            if (mounted) setState(() {});
          },
          child: const Text('Eigen provider / satellietstijl gebruiken'),
        ),
        const Text(
          'Eigen stijl vereist een geldige providerconfiguratie en toegestane gebruiksrechten. Satelliet is alleen beschikbaar wanneer die stijl echte satellietbronnen bevat. Gebiedsdownload voor eigen providers is niet automatisch toegestaan. Google Maps is geen MapLibre-provider en is niet geconfigureerd.',
        ),
        SwitchListTile(
          title: const Text('Uitsluitend offline kaarten gebruiken'),
          value: Runtime.settings.value('mapOffline', false),
          onChanged: (v) async {
            await ml.setOffline(v);
            await Runtime.settings.set('mapOffline', v);
            if (mounted) setState(() {});
          },
        ),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const OfflineMapsScreen()),
          ),
          icon: const Icon(Icons.download_outlined),
          label: const Text('Offline gebieden beheren'),
        ),
        if (Runtime.settings.value<String?>('offlineMap', null) != null)
          TextButton(
            onPressed: () async {
              await Runtime.settings.set('mapEngine', 'raster');
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Geïmporteerde raster-MBTiles gebruiken'),
          ),
        if (error != null) Text(error!),
      ],
    ),
  );
  @override
  void dispose() {
    url.dispose();
    super.dispose();
  }
}

class _AreaPicker extends StatefulWidget {
  const _AreaPicker();
  @override
  State<_AreaPicker> createState() => _AreaPickerState();
}

class _AreaPickerState extends State<_AreaPicker> {
  LatLng? first, second;
  List<double>? get bounds => first == null || second == null
      ? null
      : [
          first!.latitude < second!.latitude
              ? first!.latitude
              : second!.latitude,
          first!.longitude < second!.longitude
              ? first!.longitude
              : second!.longitude,
          first!.latitude > second!.latitude
              ? first!.latitude
              : second!.latitude,
          first!.longitude > second!.longitude
              ? first!.longitude
              : second!.longitude,
        ];
  @override
  Widget build(BuildContext context) {
    final b = bounds;
    final outline = b == null
        ? null
        : NavRoute('Geselecteerde gebiedsgrens', [
            NavPoint(b[0], b[1]),
            NavPoint(b[2], b[1]),
            NavPoint(b[2], b[3]),
            NavPoint(b[0], b[3]),
            NavPoint(b[0], b[1]),
          ]);
    return Scaffold(
      appBar: AppBar(title: const Text('Gebied kiezen')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              first == null
                  ? 'Verschuif en zoom de kaart. Houd de eerste hoek ingedrukt.'
                  : second == null
                  ? 'Houd de tegenoverliggende hoek ingedrukt.'
                  : 'De lijn toont je gebiedsgrens. Houd opnieuw ingedrukt om opnieuw te kiezen.',
            ),
          ),
          Expanded(
            child: VectorRouteMap(
              route: outline,
              onLongPress: (p) => setState(() {
                if (first == null || second != null) {
                  first = p;
                  second = null;
                } else {
                  second = p;
                }
              }),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed: b == null ? null : () => Navigator.pop(context, b),
                child: const Text('Dit gebied gebruiken'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class OfflineMapsScreen extends StatefulWidget {
  const OfflineMapsScreen({super.key});
  @override
  State<OfflineMapsScreen> createState() => _OfflineMapsScreenState();
}

class _OfflineMapsScreenState extends State<OfflineMapsScreen> {
  final manager = OfflineMaps.instance,
      name = TextEditingController(text: 'Mijn fietsgebied');
  final south = TextEditingController(),
      west = TextEditingController(),
      north = TextEditingController(),
      east = TextEditingController();
  double minZoom = 10, maxZoom = 14;
  String? error;
  int free = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await PlatformBridge.call<Map>('diagnostics');
      if (mounted) {
        setState(() => free = (data?['freeBytes'] as num?)?.toInt() ?? 0);
      }
      await manager.load();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> _manage(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> _around() async {
    try {
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
      }
      if (p == LocationPermission.denied ||
          p == LocationPermission.deniedForever) {
        throw StateError('Locatietoegang ontbreekt');
      }
      final loc = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          timeLimit: Duration(seconds: 20),
        ),
      );
      _bounds(
        loc.latitude - .01,
        loc.longitude - .015,
        loc.latitude + .01,
        loc.longitude + .015,
      );
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  void _bounds(double s, double w, double n, double e) {
    setState(() {
      south.text = s.toStringAsFixed(5);
      west.text = w.toStringAsFixed(5);
      north.text = n.toStringAsFixed(5);
      east.text = e.toStringAsFixed(5);
    });
  }

  Future<void> _chooseMap() async {
    final bounds = await Navigator.push<List<double>>(
      context,
      MaterialPageRoute(builder: (_) => const _AreaPicker()),
    );
    if (bounds != null && mounted) {
      _bounds(bounds[0], bounds[1], bounds[2], bounds[3]);
    }
  }

  Future<void> _place() async {
    final query = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Plaats of regio zoeken'),
        content: TextField(
          controller: query,
          decoration: const InputDecoration(
            labelText: 'Plaatsnaam · openrouteservice',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, query.text),
            child: const Text('Zoeken'),
          ),
        ],
      ),
    );
    query.dispose();
    if (text == null) return;
    final client = RoutingClient();
    try {
      final key = await const FlutterSecureStorage().read(key: 'ors-key') ?? '';
      final results = await client.search(text, key);
      if (!mounted) return;
      final selected = await showDialog<NavPoint>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Kies een plaats'),
          children: [
            if (results.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('Geen resultaten.'),
              ),
            for (final r in results)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, r.point),
                child: Text(r.label),
              ),
          ],
        ),
      );
      if (selected != null && mounted) {
        _bounds(
          selected.lat - .01,
          selected.lon - .015,
          selected.lat + .01,
          selected.lon + .015,
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      client.dispose();
    }
  }

  Future<void> _route() async {
    try {
      final raw = await Runtime.database.getDocument('navigation', 'selected');
      if (raw == null) throw StateError('Selecteer eerst een route');
      final r = NavRoute.decode(raw);
      var s = 90.0, n = -90.0, w = 180.0, e = -180.0;
      for (final p in r.points) {
        if (p.lat < s) s = p.lat;
        if (p.lat > n) n = p.lat;
        if (p.lon < w) w = p.lon;
        if (p.lon > e) e = p.lon;
      }
      _bounds(s - .003, w - .003, n + .003, e + .003);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  DownloadBounds get area => DownloadBounds(
    double.parse(south.text),
    double.parse(west.text),
    double.parse(north.text),
    double.parse(east.text),
    minZoom.round(),
    maxZoom.round(),
  );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: manager,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: const Text('Offline kaarten'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Voor vertrek downloaden',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Text('Vrije opslag: ${(free / 1048576).toStringAsFixed(0)} MB'),
          const Text(
            'OpenFreeMap staat kleine offline gebieden toe. Maximaal 2.500 geraamde tegels, 48 MB en vier gelijktijdige verzoeken. Een gebied is pas beschikbaar wanneer de native volledigheidscontrole slaagt.',
          ),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: _around,
                child: const Text('Rond mijn locatie'),
              ),
              OutlinedButton(
                onPressed: _route,
                child: const Text('Langs mijn route'),
              ),
              OutlinedButton(
                onPressed: _chooseMap,
                child: const Text('Gebied op kaart kiezen'),
              ),
              OutlinedButton(
                onPressed: _place,
                child: const Text('Plaats zoeken'),
              ),
            ],
          ),
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Gebiedsnaam'),
          ),
          for (final entry in [
            ('Zuid', south),
            ('West', west),
            ('Noord', north),
            ('Oost', east),
          ])
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextField(
                controller: entry.$2,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: InputDecoration(labelText: entry.$1),
              ),
            ),
          Text('Zoom ${minZoom.round()} – ${maxZoom.round()}'),
          RangeSlider(
            values: RangeValues(minZoom, maxZoom),
            min: 0,
            max: 16,
            divisions: 16,
            onChanged: (v) => setState(() {
              minZoom = v.start;
              maxZoom = v.end;
            }),
          ),
          Builder(
            builder: (_) {
              try {
                return Text(
                  '${area.tiles} geraamde vectortegels · bestandsgrootte wordt tijdens downloaden gemeten',
                );
              } catch (_) {
                return const Text('Kies eerst een gebied');
              }
            },
          ),
          FilledButton.icon(
            key: const ValueKey('download-area'),
            onPressed: manager.starting
                ? null
                : () async {
                    try {
                      if (mounted) setState(() => error = null);
                      final a = area;
                      a.validate();
                      if (Runtime.settings.value('mapStyle', 'dark') ==
                          'custom') {
                        throw StateError(
                          'Kies eerst een OpenFreeMap-stijl. Downloads voor eigen providers vereisen afzonderlijke toestemming.',
                        );
                      }
                      final style = MapStyleSpec.builtins.firstWhere(
                        (s) =>
                            s.id == Runtime.settings.value('mapStyle', 'dark'),
                        orElse: () => MapStyleSpec.builtins.first,
                      );
                      final yes = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Gebied downloaden?'),
                          content: Text(
                            '${a.tiles} tegels · ${style.name}. Maximaal 48 MB. De vrije opslag wordt vóór starten gecontroleerd.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Annuleren'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Downloaden'),
                            ),
                          ],
                        ),
                      );
                      if (yes == true) {
                        await Runtime.settings.set('mapOffline', false);
                        await ml.setOffline(false);
                        await manager.download(name.text, a, style);
                      }
                    } catch (e) {
                      if (mounted) setState(() => error = e.toString());
                    }
                  },
            icon: const Icon(Icons.download),
            label: const Text('Download starten'),
          ),
          if (error != null || manager.error != null)
            Text(
              error ?? manager.error!,
              style: const TextStyle(color: Colors.orange),
            ),
          if (manager.regions.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Nog geen gedownloade gebieden.'),
            ),
          for (final r in manager.regions)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${r.metadata['name'] ?? 'Gebied ${r.id}'}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      '${r.metadata['style'] ?? r.definition.mapStyleUrl} · zoom ${r.definition.minZoom.round()}–${r.definition.maxZoom.round()}',
                    ),
                    Text('${r.metadata['created'] ?? ''}'),
                    Text(
                      manager.statuses[r.id]?.isComplete == true
                          ? 'Volledig offline beschikbaar'
                          : 'Onvolledig · downloaden, gepauzeerd of opnieuw proberen',
                    ),
                    LinearProgressIndicator(
                      value: manager.statuses[r.id]?.downloadProgress.clamp(
                        0,
                        1,
                      ),
                    ),
                    Text(
                      '${((manager.statuses[r.id]?.completedResourceSize ?? 0) / 1048576).toStringAsFixed(1)} MB lokaal',
                    ),
                    Wrap(
                      children: [
                        TextButton(
                          onPressed: () => _manage(() => manager.pause(r.id)),
                          child: const Text('Pauze'),
                        ),
                        TextButton(
                          onPressed: () => _manage(() async {
                            await Runtime.settings.set('mapOffline', false);
                            await ml.setOffline(false);
                            await manager.resume(r.id);
                          }),
                          child: const Text('Hervat / retry'),
                        ),
                        TextButton(
                          onPressed: () async {
                            await Runtime.settings.set(
                              'mapStyle',
                              MapStyleSpec.builtins
                                  .firstWhere(
                                    (s) => s.url == r.definition.mapStyleUrl,
                                    orElse: () => MapStyleSpec.builtins.first,
                                  )
                                  .id,
                            );
                            await Runtime.settings.set('mapEngine', 'vector');
                            await Runtime.settings.set('offlineView', {
                              'lat':
                                  (r.definition.bounds.southwest.latitude +
                                      r.definition.bounds.northeast.latitude) /
                                  2,
                              'lon':
                                  (r.definition.bounds.southwest.longitude +
                                      r.definition.bounds.northeast.longitude) /
                                  2,
                              'zoom': r.definition.maxZoom,
                              'id': r.id,
                            });
                            await Runtime.settings.set('mapOffline', true);
                            await ml.setOffline(true);
                            if (context.mounted) Navigator.pop(context);
                          },
                          child: const Text('Offline gebruiken'),
                        ),
                        TextButton(
                          onPressed: () => _manage(() => manager.remove(r.id)),
                          child: const Text('Annuleren / verwijderen'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
  @override
  void dispose() {
    for (final c in [name, south, west, north, east]) {
      c.dispose();
    }
    super.dispose();
  }
}
