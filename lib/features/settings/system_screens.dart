import 'dart:convert';

import '../more/android_apps_screen.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:bike_computer/core/runtime.dart';
import 'package:bike_computer/core/platform_bridge.dart';
import 'package:bike_computer/features/ride/ride_screen.dart';
import 'package:bike_computer/features/integrations/connected_apps_screen.dart';

class AppsScreen extends StatelessWidget {
  const AppsScreen({super.key});
  @override
  Widget build(BuildContext context) => const AndroidAppsScreen();
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
