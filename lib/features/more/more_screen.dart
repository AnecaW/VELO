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
      ('Dashboard', Icons.space_dashboard_outlined, null),
      ('Fietscomputer', Icons.speed_rounded, null),
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
      ('Verbonden apps', Icons.hub_outlined, const IntegrationsScreen()),
      ('Activiteitprofielen', Icons.directions_bike, const ProfilesScreen()),
      ('Telefoon-apps', Icons.apps, const AppsScreen()),
      ('Instellingen', Icons.settings_outlined, const SettingsScreen()),
      ('Diagnostiek', Icons.monitor_heart_outlined, const DiagnosticsScreen()),
      ('Klimprofiel', Icons.terrain, const ClimbScreen()),
    ];
    final filtered = entries
        .where((e) => e.$1.toLowerCase().contains(search.toLowerCase()))
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('VELO-functies')),
      body: CustomScrollView(
        key: const ValueKey('more-list'),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Alles voor je rit.',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Je fietscomputer, kaarten en persoonlijke hulpmiddelen.',
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    decoration: const InputDecoration(
                      hintText: 'Zoek een onderdeel',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (v) => setState(() => search = v),
                  ),
                ],
              ),
            ),
          ),
          if (filtered.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Geen onderdelen gevonden.'),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) => SliverGrid.builder(
                itemCount: filtered.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: constraints.crossAxisExtent >= 600 ? 3 : 2,
                  mainAxisExtent: 126,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemBuilder: (context, i) {
                  final e = filtered[i];
                  return Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: () {
                        if (e.$3 == null) {
                          if (e.$1 == 'Dashboard') {
                            context.push('/home');
                          } else {
                            context.go(
                              e.$1 == 'Fietscomputer' ? '/ride' : '/navigation',
                            );
                          }
                        } else {
                          Navigator.push(
                            context,
                            MaterialPageRoute<void>(builder: (_) => e.$3!),
                          );
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Icon(
                              e.$2,
                              size: 30,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            Text(
                              e.$1,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
