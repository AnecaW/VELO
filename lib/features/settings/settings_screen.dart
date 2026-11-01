import 'package:bike_computer/features/profiles/profiles_screen.dart';

import '../accounts/account_screen.dart';
import 'data_settings_screen.dart';
import '../../widgets/velo_ui.dart';
import '../more/android_apps_screen.dart';

import 'package:bike_computer/features/settings/appearance_screen.dart';
import 'package:bike_computer/features/maps/map_settings_screen.dart';
import 'package:bike_computer/features/training/training_screen.dart';

import 'dart:convert';

import 'package:bike_computer/services/storage/backup_service.dart';

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:bike_computer/core/runtime.dart';
import 'package:bike_computer/core/platform_bridge.dart';
import 'package:bike_computer/features/settings/sensors_screen.dart';
import 'package:bike_computer/features/settings/system_screens.dart';
import 'package:bike_computer/widgets/route_map.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? error;
  Future<void> _set(String key, dynamic value) async {
    try {
      await Runtime.settings.set(key, value);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Widget _section(String title, IconData icon, VoidCallback action) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    trailing: const Icon(Icons.chevron_right),
    onTap: action,
  );
  void _page(Widget page) =>
      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));
  Future<void> _dialog(
    String title,
    List<Widget> Function(StateSetter) content,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: content(update),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Sluiten'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _switch(String title, String key, bool fallback, StateSetter update) =>
      SwitchListTile(
        title: Text(title),
        value: Runtime.settings.value(key, fallback),
        onChanged: (v) async {
          await _set(key, v);
          update(() {});
        },
      );

  Future<void> _offline() async {
    try {
      final files = await FilePicker.pickFiles(type: FileType.any);
      if (files.isEmpty) return;
      final length = await files.first.length();
      if (length == null || length > 2 * 1024 * 1024 * 1024) {
        throw StateError('Kaart maximaal 2 GB');
      }
      final directory = await getApplicationSupportDirectory();
      final target = File(
        '${directory.path}/offline-${DateTime.now().millisecondsSinceEpoch}.mbtiles',
      );
      try {
        final sink = target.openWrite();
        await sink.addStream(files.first.readAsByteStream());
        await sink.close();
        final provider = MbTilesProvider(target.path);
        try {
          final metadata = provider.database.select(
            'SELECT name,value FROM metadata',
          );
          final format = metadata
              .where((r) => r['name'] == 'format')
              .firstOrNull?['value'];
          if (format != null &&
              !['png', 'jpg', 'jpeg', 'webp'].contains(format)) {
            throw StateError('Alleen raster MBTiles (PNG/JPEG/WebP)');
          }
        } finally {
          await provider.dispose();
        }
        await _set('offlineMap', target.path);
      } catch (_) {
        if (await target.exists()) await target.delete();
        rethrow;
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Instellingen')),
    body: SafeArea(
      top: false,
      child: ListView(
        padding: VeloSpace.insets,
        children: [
          if (error != null) VeloNotice(error!, error: true),
          VeloSection(
            title: 'Account',
            children: [
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('Accountgegevens'),
                subtitle: Text(
                  Runtime.accounts.user?['email'] ??
                      'Aanmelden of een account aanmaken',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _page(const AccountScreen()),
              ),
            ],
          ),
          VeloSection(
            title: 'Weergave',
            children: [
              _section(
                'OLED & uiterlijk',
                Icons.palette_outlined,
                () => _page(const AppearanceScreen()),
              ),
              _section(
                'Scherminstellingen',
                Icons.brightness_4,
                () => _dialog(
                  'Scherminstellingen',
                  (update) => [
                    _switch('Scherm aan tijdens rit', 'keepOn', true, update),
                    const Text(
                      'Scherm vastzetten gebruikt de Android-bevestiging. Ontgrendel via de systeemtoetsen van je toestel.',
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        try {
                          await PlatformBridge.call('pin');
                        } catch (_) {
                          if (mounted) {
                            setState(
                              () => error = 'Vastzetten is niet beschikbaar op dit toestel.',
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.push_pin_outlined),
                      label: const Text('VELO vastzetten'),
                    ),
                    TextButton(
                      onPressed: () async {
                        await PlatformBridge.call('unpin');
                      },
                      child: const Text('Vastzetten stoppen'),
                    ),
                    const Text('Schermhelderheid tijdens rit'),
                    Slider(
                      value: Runtime.settings.value('brightness', 0.8),
                      min: 0.1,
                      max: 1,
                      onChanged: (v) async {
                        await _set('brightness', v);
                        await PlatformBridge.call('display', {
                          'brightness': v,
                          'keepOn': Runtime.settings.value('keepOn', true),
                        });
                        update(() {});
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          VeloSection(
            title: 'Fietscomputer',
            children: [
              _section(
                'Activiteitprofielen',
                Icons.directions_bike,
                () => _page(const ProfilesScreen()),
              ),
              _section(
                'Eenheden',
                Icons.straighten,
                () => _dialog(
                  'Eenheden',
                  (update) => [
                    RadioGroup<bool>(
                      groupValue: Runtime.settings.value('imperial', false),
                      onChanged: (v) async {
                        await _set('imperial', v);
                        update(() {});
                      },
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          RadioListTile<bool>(
                            title: Text('Metrisch · km, km/h, m, °C'),
                            value: false,
                          ),
                          RadioListTile<bool>(
                            title: Text('Imperiaal · mi, mph, ft, °F'),
                            value: true,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _section(
                'GPS en opname',
                Icons.gps_fixed,
                () => _dialog(
                  'GPS en opname',
                  (update) => [
                    _switch(
                      'Hoge GPS-nauwkeurigheid',
                      'highAccuracy',
                      true,
                      update,
                    ),
                    _switch(
                      'Automatische pauze (<3 km/h, 5 s)',
                      'autoPause',
                      false,
                      update,
                    ),
                    const Text('GPS-interval · seconden (volgende rit)'),
                    Slider(
                      value: Runtime.settings
                          .value('gpsInterval', 2)
                          .toDouble(),
                      min: 1,
                      max: 10,
                      divisions: 9,
                      label: '${Runtime.settings.value('gpsInterval', 2)} s',
                      onChanged: (v) async {
                        await _set('gpsInterval', v.round());
                        update(() {});
                      },
                    ),
                    const Text('Maximale horizontale GPS-fout'),
                    Slider(
                      value: Runtime.settings.value('maxAccuracy', 50.0),
                      min: 10,
                      max: 100,
                      divisions: 9,
                      label:
                          '${Runtime.settings.value('maxAccuracy', 50.0).round()} m',
                      onChanged: (v) async {
                        await _set('maxAccuracy', v);
                        update(() {});
                      },
                    ),
                  ],
                ),
              ),
              _section(
                'Sensoren',
                Icons.bluetooth,
                () => _page(const SensorsScreen()),
              ),
              _section(
                'Voeding & hydratatie',
                Icons.water_drop_outlined,
                () => _dialog(
                  'Herinneringen',
                  (update) => [
                    for (final pair in [
                      ('drinkMinutes', 'Drinken'),
                      ('foodMinutes', 'Voeding'),
                    ])
                      Column(
                        children: [
                          Text(
                            '${pair.$2}: ${Runtime.settings.value(pair.$1, 0)} min (0 = uit)',
                          ),
                          Slider(
                            value: Runtime.settings
                                .value(pair.$1, 0)
                                .toDouble(),
                            min: 0,
                            max: 120,
                            divisions: 24,
                            onChanged: (v) async {
                              await _set(pair.$1, v.round());
                              update(() {});
                            },
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
          VeloSection(
            title: 'Kaart en navigatie',
            children: [
              _section(
                'Kaartprovider & stijl',
                Icons.layers_outlined,
                () => _page(const MapSettingsScreen()),
              ),
              _section(
                'Navigatie',
                Icons.near_me,
                () => _dialog(
                  'Navigatie-opties',
                  (update) => [
                    _switch(
                      'Online OpenStreetMap · deelt kaartgebied',
                      'onlineMap',
                      false,
                      update,
                    ),
                    _switch(
                      'Automatisch herberekenen',
                      'reroute',
                      false,
                      update,
                    ),
                    _switch('Gesproken aanwijzingen', 'voice', false, update),
                    const Text('Routeringprofiel (provider ondersteund)'),
                    DropdownButton<String>(
                      value: Runtime.settings.value(
                        'routingProfile',
                        'cycling-regular',
                      ),
                      isExpanded: true,
                      items: [
                        for (final p in [
                          'cycling-regular',
                          'cycling-road',
                          'cycling-mountain',
                          'cycling-electric',
                        ])
                          DropdownMenuItem(value: p, child: Text(p)),
                      ],
                      onChanged: (v) async {
                        await _set('routingProfile', v);
                        update(() {});
                      },
                    ),
                    const Text(
                      'GPX-begeleiding werkt offline. Voor nieuwe routes en herberekening heb je verbinding met VELO nodig.',
                    ),
                  ],
                ),
              ),
              _section(
                'Offline gebieden',
                Icons.download_outlined,
                () => _page(const OfflineMapsScreen()),
              ),
              _section(
                'Rasterkaart importeren',
                Icons.map,
                () => _dialog(
                  'Offline kaarten',
                  (update) => [
                    Text(
                      Runtime.settings.value<String?>('offlineMap', null) ==
                              null
                          ? 'Geen offline achtergrondkaart'
                          : 'Raster MBTiles geïmporteerd. Controleer dekking en zoomniveaus vóór vertrek.',
                    ),
                    FilledButton(
                      onPressed: () async {
                        await _offline();
                        update(() {});
                      },
                      child: const Text('Importeer raster MBTiles'),
                    ),
                    TextButton(
                      onPressed: () async {
                        final path = Runtime.settings.value<String?>(
                          'offlineMap',
                          null,
                        );
                        await _set('offlineMap', null);
                        if (path != null && await File(path).exists()) {
                          await File(path).delete();
                        }
                        update(() {});
                      },
                      child: const Text('Offline kaart verwijderen'),
                    ),
                    const Text(
                      'Gebruik uitsluitend kaarten waarvoor je offline gebruiksrechten hebt. Geen bulkdownload van openbare OSM-tiles.',
                    ),
                  ],
                ),
              ),
            ],
          ),
          VeloSection(
            title: 'Training',
            children: [
              _section(
                'Trainingsprofiel & generator',
                Icons.fitness_center,
                () => _page(const TrainingScreen()),
              ),
              _section(
                'Training · FTP',
                Icons.fitness_center,
                () => _dialog(
                  'Trainingzones',
                  (update) => [
                    Text(
                      'FTP: ${Runtime.settings.value('ftp', 0.0) == 0 ? 'niet ingesteld' : Runtime.settings.value('ftp', 0.0).round()} W',
                    ),
                    Slider(
                      value: Runtime.settings
                          .value('ftp', 50.0)
                          .clamp(50.0, 600.0),
                      min: 50,
                      max: 600,
                      divisions: 110,
                      onChanged: (v) async {
                        await _set('ftp', v);
                        update(() {});
                      },
                    ),
                    const Text(
                      'Vermogenszones: ≤55%, ≤75%, ≤90%, ≤105%, ≤120%, ≤150%, >150% van FTP. Stel je eigen gemeten FTP in vóór een training.',
                    ),
                  ],
                ),
              ),
            ],
          ),
          VeloSection(
            title: 'Integraties',
            children: [
              _section(
                'Verbonden diensten',
                Icons.hub_outlined,
                () => _page(const IntegrationsScreen()),
              ),
            ],
          ),
          VeloSection(
            title: 'Gegevens en privacy',
            children: [
              _section(
                'Synchronisatie en privacy',
                Icons.privacy_tip_outlined,
                () => _page(const DataSettingsScreen()),
              ),
              _section(
                'Back-up & herstellen',
                Icons.backup,
                () => _dialog(
                  'Gegevensbeheer',
                  (update) => [
                    const Text(
                      'Een back-up bevat persoonlijke GPS-sporen, routes en instellingen. Je aanmeldgegevens worden niet meegenomen. Bewaar het bestand zelf veilig.',
                    ),
                    FilledButton(
                      onPressed: () async {
                        try {
                          final data = await BackupService(Runtime.database)
                              .export();
                          await FilePicker.saveFile(
                            fileName: 'bike-backup.json',
                            mimeType: 'application/json',
                            bytes: Uint8List.fromList(utf8.encode(data)),
                          );
                        } catch (e) {
                          if (mounted) setState(() => error = e.toString());
                        }
                      },
                      child: const Text('Back-up exporteren'),
                    ),
                    OutlinedButton(
                      onPressed: () async {
                        try {
                          final files = await FilePicker.pickFiles(
                            type: FileType.any,
                          );
                          if (files.isEmpty) return;
                          final length = await files.first.length();
                          if (length == null || length > 50 * 1024 * 1024) {
                            throw StateError('Maximaal 50 MB');
                          }
                          await BackupService(Runtime.database).restore(
                            utf8.decode(await files.first.readAsBytes()),
                          );
                          await Runtime.settings.load();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Back-up hersteld; bestaande ritten behouden',
                                ),
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) setState(() => error = e.toString());
                        }
                      },
                      child: const Text('Back-up importeren'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          VeloSection(
            title: 'Over VELO',
            children: [
              FutureBuilder<Map?>(
                future: PlatformBridge.call<Map>('appInfo'),
                builder: (context, snapshot) => ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('Versie en informatie'),
                  subtitle: Text(
                    snapshot.data == null
                        ? 'VELO'
                        : '${snapshot.data!['version']} (${snapshot.data!['build']})',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showAboutDialog(
                    context: context,
                    applicationName: 'VELO',
                    applicationVersion: snapshot.data?['version'],
                    children: const [
                      Text(
                        'Je fietscomputer, ritten, kaarten en trainingen op één plek.',
                      ),
                    ],
                  ),
                ),
              ),
              _section(
                'Licenties',
                Icons.description_outlined,
                () =>
                    showLicensePage(context: context, applicationName: 'VELO'),
              ),
              _section(
                'Diagnostiek',
                Icons.monitor_heart_outlined,
                () => _page(const DiagnosticsScreen()),
              ),
              _section(
                'Android-apps',
                Icons.apps,
                () => _page(const AndroidAppsScreen()),
              ),
            ],
          ),
          if (kDebugMode)
            VeloSection(
              title: 'Ontwikkeling',
              children: [
                _section(
                  'Ontwikkelmodus',
                  Icons.science,
                  () => _page(const SimulationScreen()),
                ),
              ],
            ),
        ],
      ),
    ),
  );
}
