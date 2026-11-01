import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:bike_computer/core/runtime.dart';
import 'package:bike_computer/core/platform_bridge.dart';
import 'package:bike_computer/features/profiles/cubits/activity_profile_cubit.dart';
import 'package:bike_computer/services/ride/ride_history_service.dart';
import 'package:bike_computer/services/training/training_generator.dart';
import 'package:bike_computer/models/ride_session.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => ActivityProfileCubit()..loadProfiles(),
    child: const _Dashboard(),
  );
}

class _Dashboard extends StatefulWidget {
  const _Dashboard();
  @override
  State<_Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<_Dashboard> {
  List<RideSession> rides = [];
  List<TrainingPlan> plans = [];
  int? battery;
  bool? gps;
  String? error;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    _load();
    timer = Timer.periodic(const Duration(minutes: 1), (_) => _load());
    Runtime.settings.addListener(_changed);
  }

  void _changed() {
    if (mounted) {
      context.read<ActivityProfileCubit>().loadProfiles();
      setState(() {});
    }
  }

  Future<void> _load() async {
    try {
      final history = RideHistoryService(database: Runtime.database);
      await history.loadPersistedRides();
      final p = await TrainingStore(Runtime.database).plans();
      Map? d;
      try {
        d = await PlatformBridge.call<Map>('diagnostics');
        gps = await Geolocator.isLocationServiceEnabled();
      } catch (_) {}
      if (mounted) {
        setState(() {
          rides = history.getRidesSortedByDate();
          plans = p;
          battery = d?['battery'] as int?;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final start = DateTime.now().subtract(
      Duration(days: DateTime.now().weekday - 1),
    );
    final week = rides.where(
      (r) =>
          r.startTime != null &&
          r.startTime!.isAfter(DateTime(start.year, start.month, start.day)),
    );
    final km = week.fold(0.0, (a, r) => a + r.totalDistance),
        seconds = week.fold(0, (a, r) => a + r.movingTime.inSeconds),
        gain = week.fold(0.0, (a, r) => a + r.totalElevationGain);
    final hidden = Runtime.settings.value<List<dynamic>>('hiddenWidgets', []);
    final scheduled = plans
        .where(
          (p) =>
              p.scheduled == DateTime.now().toIso8601String().substring(0, 10),
        )
        .firstOrNull;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'VELO',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 5,
                    ),
                  ),
                  Text(
                    TimeOfDay.now().format(context),
                    style: const TextStyle(fontSize: 15),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Text(
                'Klaar voor\nde volgende rit.',
                style: Theme.of(context).textTheme.headlineLarge
                    ?.copyWith(fontSize: 36, letterSpacing: -1.4, height: 1.08),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _status(
                    Icons.battery_std,
                    battery == null ? 'Batterij —' : '$battery%',
                  ),
                  _status(
                    Icons.gps_fixed,
                    gps == null
                        ? 'GPS-status —'
                        : gps!
                        ? 'Locatie aan'
                        : 'Locatie uit',
                  ),
                  _status(
                    Icons.bluetooth,
                    '${Runtime.sensors.connectedSensors.length} sensoren',
                  ),
                ],
              ),
              const SizedBox(height: 22),
              BlocBuilder<ActivityProfileCubit, ActivityProfileState>(
                builder: (context, state) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.selectedProfile?.name ?? 'Activiteit',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final p in state.profiles)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                key: ValueKey('profile-chip-${p.id}'),
                                label: Text(p.name),
                                selected: state.selectedProfile?.id == p.id,
                                onSelected: (_) => context
                                    .read<ActivityProfileCubit>()
                                    .selectProfile(p.id),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              ListenableBuilder(
                listenable: Runtime.ride,
                builder: (context, _) => FilledButton.icon(
                  onPressed: () => context.go('/ride'),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(
                    Runtime.ride.session.isRecording
                        ? 'Terug naar actieve rit'
                        : 'START RIDE',
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 64),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              if (!hidden.contains('week')) ...[
                _heading('DEZE WEEK'),
                Row(
                  children: [
                    Expanded(
                      child: _metric(km.toStringAsFixed(1), 'kilometer'),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _metric(
                        '${seconds ~/ 3600}h ${(seconds ~/ 60) % 60}m',
                        'in beweging',
                      ),
                    ),
                  ],
                ),
                _metric('${gain.round()} m', 'hoogtemeters · GPS'),
                const SizedBox(height: 18),
              ],
              if (!hidden.contains('last')) ...[
                _heading('LAATSTE RIT'),
                if (rides.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.route_outlined, size: 30),
                          const SizedBox(height: 12),
                          const Text(
                            'Je eerste rit begint hier.',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Text(
                            'Nog geen ritten opgeslagen. Neem een echte rit op om je voortgang te zien.',
                          ),
                          TextButton(
                            onPressed: () => context.go('/ride'),
                            child: const Text('Start een rit'),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.north_east),
                      title: Text(
                        '${rides.first.totalDistance.toStringAsFixed(1)} km',
                      ),
                      subtitle: Text(
                        '${rides.first.startTime?.toLocal().toString().substring(0, 16) ?? 'Opgeslagen rit'} · ${rides.first.movingTime.inMinutes} min',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/history'),
                    ),
                  ),
              ],
              if (!hidden.contains('planned')) ...[
                _heading('TRAINING'),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.event_outlined),
                    title: Text(scheduled?.name ?? 'Ruimte voor jouw doel'),
                    subtitle: Text(
                      scheduled == null
                          ? 'Stel lokaal een training samen'
                          : 'Vandaag gepland · ${scheduled.seconds ~/ 60} min',
                    ),
                    onTap: () => context.go('/training'),
                  ),
                ),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => context.go('/navigation'),
                      icon: const Icon(Icons.near_me_outlined),
                      label: const Text('Navigeren'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => context.go('/training'),
                      icon: const Icon(Icons.fitness_center),
                      label: const Text('Training'),
                    ),
                  ),
                ],
              ),
              TextButton(
                onPressed: () => _customize(),
                child: const Text('Dashboard aanpassen'),
              ),
              if (error != null)
                Text(error!, style: const TextStyle(color: Colors.orange)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _status(IconData icon, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      border: Border.all(
        color: Theme.of(context).colorScheme.outline.withValues(alpha: .35),
      ),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 11)),
      ],
    ),
  );
  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 10),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        letterSpacing: 2,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
  Widget _metric(String value, String label) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              letterSpacing: -1,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurface
                  .withValues(alpha: .6),
            ),
          ),
        ],
      ),
    ),
  );
  Future<void> _customize() => showModalBottomSheet<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Dashboardwidgets')),
            for (final p in [
              ('week', 'Weekoverzicht'),
              ('last', 'Laatste rit'),
              ('planned', 'Geplande training'),
            ])
              CheckboxListTile(
                title: Text(p.$2),
                value: !Runtime.settings
                    .value<List<dynamic>>('hiddenWidgets', [])
                    .contains(p.$1),
                onChanged: (v) async {
                  final values = [
                    ...Runtime.settings.value<List<dynamic>>(
                      'hiddenWidgets',
                      [],
                    ),
                  ];
                  if (v == true) {
                    values.remove(p.$1);
                  } else {
                    values.add(p.$1);
                  }
                  await Runtime.settings.set('hiddenWidgets', values);
                  update(() {});
                },
              ),
          ],
        ),
      ),
    ),
  );
  @override
  void dispose() {
    timer?.cancel();
    Runtime.settings.removeListener(_changed);
    super.dispose();
  }
}
