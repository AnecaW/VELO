import 'package:bike_computer/features/accounts/account_screen.dart';
import 'package:bike_computer/features/profiles/profiles_screen.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:bike_computer/features/settings/settings_screen.dart';
import 'package:bike_computer/features/settings/system_screens.dart';
import 'package:bike_computer/features/settings/sensors_screen.dart';
import 'package:bike_computer/features/history/history_screen.dart';
import 'package:bike_computer/features/analytics/analytics_screens.dart';
import 'package:bike_computer/features/maps/map_settings_screen.dart';
import 'package:bike_computer/features/training/training_screen.dart';

class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});
  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  String search = '';
  @override
  Widget build(BuildContext context) {
    final entries = <(String, IconData, Widget?)>[
      ('VELO-account', Icons.person_outline, const AccountScreen()),
      ('Ritten', Icons.history, const HistoryScreen()),
      ('Statistieken', Icons.insights, const StatisticsScreen()),
      ('Routes', Icons.route, null),
      (
        'Offline kaarten',
        Icons.download_for_offline_outlined,
        const OfflineMapsScreen(),
      ),
      ('Kaartbronnen', Icons.layers_outlined, const MapSettingsScreen()),
      ('Sensoren', Icons.bluetooth, const SensorsScreen()),
      ('Trainingsbibliotheek', Icons.fitness_center, const TrainingScreen()),
      (
        'Trainingsgeschiedenis',
        Icons.event_available,
        const TrainingScreen(history: true),
      ),
      ('Strava', Icons.sync, const IntegrationsScreen()),
      ('Verbonden apps', Icons.hub_outlined, const IntegrationsScreen()),
      ('Activiteitprofielen', Icons.directions_bike, const ProfilesScreen()),
      ('Apps', Icons.apps, const AppsScreen()),
      ('Instellingen', Icons.settings_outlined, const SettingsScreen()),
      ('Diagnostiek', Icons.monitor_heart_outlined, const DiagnosticsScreen()),
      ('Klimprofiel', Icons.terrain, const ClimbScreen()),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Meer')),
      body: ListView(
        key: const ValueKey('more-list'),
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            decoration: const InputDecoration(
              hintText: 'Zoek een onderdeel',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => search = v),
          ),
          const SizedBox(height: 16),
          for (final e in entries.where(
            (e) => e.$1.toLowerCase().contains(search.toLowerCase()),
          ))
            Card(
              child: ListTile(
                leading: Icon(
                  e.$2,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: Text(e.$1),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  if (e.$3 == null) {
                    context.go('/navigation');
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(builder: (_) => e.$3!),
                    );
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}
