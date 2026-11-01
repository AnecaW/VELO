import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:bike_computer/core/runtime.dart';
import 'package:bike_computer/core/platform_bridge.dart';
import 'package:bike_computer/features/ride/ride_screen.dart';
import 'package:bike_computer/features/integrations/connected_apps_screen.dart';

class AppsScreen extends StatefulWidget {
  const AppsScreen({super.key});
  @override
  State<AppsScreen> createState() => _AppsScreenState();
}

class _AppsScreenState extends State<AppsScreen> {
  List<Map<String, dynamic>> apps = [];
  String query = '', error = '';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await PlatformBridge.call<List<dynamic>>('apps') ?? [];
      if (mounted) {
        setState(
          () => apps = rows
              .map((r) => Map<String, dynamic>.from(r as Map))
              .toList(),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> _call(String method, [dynamic args]) async {
    try {
      await PlatformBridge.call(method, args);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final favorites = Runtime.settings.value<List<dynamic>>('favoriteApps', []);
    final filtered =
        apps
            .where(
              (a) =>
                  (!Runtime.settings.value('favoritesOnly', false) ||
                      favorites.contains(a['package'])) &&
                  a['name'].toString().toLowerCase().contains(
                    query.toLowerCase(),
                  ),
            )
            .toList()
          ..sort((a, b) {
            final af = favorites.contains(a['package']) ? 0 : 1,
                bf = favorites.contains(b['package']) ? 0 : 1;
            return af == bf
                ? a['name'].toString().compareTo(b['name'].toString())
                : af - bf;
          });
    return Scaffold(
      appBar: AppBar(title: const Text('Apps & Launcher')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            onPressed: () => _call('homeSettings'),
            icon: const Icon(Icons.home),
            label: const Text('Standaardlauncher instellen'),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Android vraagt je zelf een startscherm te kiezen. Herstel via Instellingen > Apps > Standaardapps > Startscherm.',
            ),
          ),
          OutlinedButton(
            onPressed: () => _call('pin'),
            child: const Text('Scherm vastzetten (Android bevestigt)'),
          ),
          TextButton(
            onPressed: () => _call('unpin'),
            child: const Text('Vastzetten verlaten'),
          ),
          const Text(
            'Scherm vastzetten is geen beheerde kiosk. Volledige lock-task vereist een device-owner en een toegestane app-lijst. Android biedt ook de systeemtoetscombinatie om los te maken.',
          ),
          SwitchListTile(
            title: const Text('Alleen favoriete apps tonen'),
            value: Runtime.settings.value('favoritesOnly', false),
            onChanged: (v) async {
              await Runtime.settings.set('favoritesOnly', v);
              if (mounted) setState(() {});
            },
          ),
          TextField(
            decoration: const InputDecoration(labelText: 'Zoek apps'),
            onChanged: (v) => setState(() => query = v),
          ),
          if (error.isNotEmpty)
            Text(error, style: const TextStyle(color: Colors.orange)),
          for (final a in filtered)
            ListTile(
              leading: const Icon(Icons.apps),
              title: Text(a['name']),
              subtitle: Text(a['package']),
              onTap: () => _call('launch', a['package']),
              trailing: IconButton(
                tooltip: 'Favoriet',
                icon: Icon(
                  favorites.contains(a['package'])
                      ? Icons.star
                      : Icons.star_border,
                ),
                onPressed: () async {
                  final next = [...favorites];
                  if (next.contains(a['package'])) {
                    next.remove(a['package']);
                  } else {
                    next.add(a['package']);
                  }
                  await Runtime.settings.set('favoriteApps', next);
                  if (mounted) setState(() {});
                },
              ),
            ),
        ],
      ),
    );
  }
}

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});
  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  Map<String, dynamic> report = {};
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = <String, dynamic>{
      'version': '2.1.0+3',
      'build': kReleaseMode ? 'release' : 'debug',
      'generated': DateTime.now().toUtc().toIso8601String(),
      'lastError': Runtime.lastError,
    };
    try {
      data.addAll(
        Map<String, dynamic>.from(
          await PlatformBridge.call<Map>('diagnostics') ?? {},
        ),
      );
    } catch (e) {
      data['device'] = e.toString();
    }
    try {
      data['locationPermission'] = (await Geolocator.checkPermission()).name;
      data['locationEnabled'] = await Geolocator.isLocationServiceEnabled();
    } catch (e) {
      data['gps'] = e.toString();
    }
    try {
      data['database'] =
          'OK · ${(await Runtime.database.getAllRides()).length} ritten';
      data['pendingSync'] = (await Runtime.database.documents('sync')).length;
    } catch (e) {
      data['database'] = e.toString();
    }
    data['connectedSensors'] = Runtime.sensors.connectedSensors.length;
    data['map'] = Runtime.settings.value<String?>('offlineMap', null) != null
        ? 'Offline MBTiles'
        : Runtime.settings.value('onlineMap', false)
        ? 'Online OSM (geen beschikbaarheidstest)'
        : 'Lokaal routespoor';
    data['routing'] = 'openrouteservice · vereist sleutel en netwerk';
    if (mounted) setState(() => report = data);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Diagnostics'),
      actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final e in report.entries)
          ListTile(title: Text(e.key), subtitle: Text('${e.value ?? '—'}')),
        FilledButton(
          onPressed: () async {
            await FilePicker.saveFile(
              fileName: 'bike-diagnostics.json',
              mimeType: 'application/json',
              bytes: Uint8List.fromList(
                utf8.encode(const JsonEncoder.withIndent('  ').convert(report)),
              ),
            );
          },
          child: const Text('Rapport exporteren (zonder tokens of GPS-spoor)'),
        ),
      ],
    ),
  );
}

class SimulationScreen extends StatelessWidget {
  const SimulationScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ontwikkelmodus')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Text(
            'SIMULATIE · geen echte metingen. Deze ritten worden niet in de echte ritgeschiedenis opgeslagen en niet gesynchroniseerd.',
          ),
          FilledButton(
            onPressed: kDebugMode
                ? () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const RideScreen(simulate: true),
                    ),
                  )
                : null,
            child: const Text('Start GPS-simulatie'),
          ),
        ],
      ),
    ),
  );
}

class IntegrationsScreen extends StatelessWidget {
  const IntegrationsScreen({super.key});
  @override
  Widget build(BuildContext context) => const ConnectedAppsScreen();
}
