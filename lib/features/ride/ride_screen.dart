import 'package:bike_computer/services/recording/ride_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:bike_computer/core/runtime.dart';
import 'package:bike_computer/core/platform_bridge.dart';
import 'package:bike_computer/models/ride_session.dart';
import 'package:bike_computer/services/ride/ride_recording_service.dart';
import 'package:bike_computer/services/ride/ride_history_service.dart';

class RideScreen extends StatefulWidget {
  final bool simulate;
  const RideScreen({super.key, this.simulate = false});
  @override
  State<RideScreen> createState() => _RideScreenState();
}

class _RideScreenState extends State<RideScreen> {
  late RideController controller;
  RideRecordingService get service => controller.service;
  RideSession get session => controller.session;
  String get profile => controller.profile;
  String? get message => controller.message;
  set message(String? value) => controller.message = value;
  int get drinks => controller.drinks;
  int get foods => controller.foods;
  Future<void> get writes => controller.writes;
  bool busy = true, locked = false;
  bool get simulation => kDebugMode && widget.simulate;
  @override
  void initState() {
    super.initState();
    controller = simulation
        ? RideController(
            Runtime.database,
            Runtime.settings,
            Runtime.sensors,
            simulate: true,
          )
        : Runtime.ride;
    controller.addListener(_changed);
    _init();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _init() async {
    try {
      await controller.initialize();
      if (controller.recovery != null && mounted) {
        final yes = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Onafgewerkte rit gevonden'),
            content: const Text(
              'Herstel je opgeslagen rit. Deze hervat gepauzeerd.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Verwijder checkpoint'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Herstellen'),
              ),
            ],
          ),
        );
        await controller.restore(yes == true);
      }
    } catch (e) {
      _error(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _error(Object e) {
    Runtime.lastError = e.toString();
    if (mounted) setState(() => message = e.toString());
  }

  Future<void> _act(Future<void> Function() action) async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await action();
    } catch (e) {
      _error(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _start() async {
    if (Runtime.settings.value('nightRide', false)) {
      await Runtime.settings.set('theme', 'oled');
    }
    try {
      await PlatformBridge.call('notifications');
    } catch (_) {}
    await controller.start();
    try {
      await PlatformBridge.call('display', {
        'keepOn': Runtime.settings.value('keepOn', true),
        'brightness': Runtime.settings.value('nightRide', false)
            ? 0.15
            : Runtime.settings.value('brightness', 0.8),
      });
    } catch (_) {}
  }

  Future<void> _finish() async {
    final finish = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rit beëindigen en opslaan?'),
        content: const Text(
          'De volledige rit en GPS-punten worden lokaal bewaard.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Verder fietsen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Opslaan'),
          ),
        ],
      ),
    );
    if (finish != true) return;
    await _act(() async {
      if (service.currentSession.state != RideState.finished) {
        await service.stopRecording();
      }
      await writes;
      final finished = service.currentSession;
      if (simulation) {
        await Runtime.database.removeDocument('simulation', 'ride');
        if (mounted) context.go('/ride/summary', extra: finished);
        return;
      }
      final history = RideHistoryService(database: Runtime.database);
      final id = await history.saveRide(finished);
      await Runtime.database.putDocument(
        'nutrition',
        id,
        '{"drinks":$drinks,"food":$foods}',
      );
      service.markAsSaved(id);
      try {
        await Runtime.integrations.rideSaved(id);
      } catch (_) {
        Runtime.lastError = 'Rit lokaal opgeslagen; automatische synchronisatie kon niet starten.';
      }
      try {
        await PlatformBridge.call('display', {
          'keepOn': false,
          'brightness': -1.0,
        });
      } catch (_) {}
      if (mounted) {
        context.go(
          '/ride/summary',
          extra: finished.copyWith(id: id, state: RideState.saved),
        );
      }
    });
  }

  Future<void> _configure() async {
    var fields = Runtime.settings.fields(profile).toList();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(ctx).height * 0.8,
            child: Column(
              children: [
                ListTile(
                  title: const Text('Gegevensvelden · versleep om te ordenen'),
                  trailing: TextButton(
                    onPressed: () async {
                      await Runtime.settings.set('fields-$profile', fields);
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) setState(() {});
                    },
                    child: const Text('Opslaan'),
                  ),
                ),
                Expanded(
                  child: ReorderableListView(
                    onReorderItem: (old, next) {
                      update(() {
                        fields.insert(next, fields.removeAt(old));
                      });
                    },
                    children: [
                      for (var i = 0; i < fields.length; i++)
                        ListTile(
                          key: ValueKey('$i-${fields[i]}'),
                          title: Text(fields[i]),
                          leading: const Icon(Icons.drag_handle),
                          trailing: IconButton(
                            onPressed: () => update(() => fields.removeAt(i)),
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                        ),
                    ],
                  ),
                ),
                Wrap(
                  children: [
                    for (final f in [
                      'Speed',
                      'Distance',
                      'Moving time',
                      'Elapsed',
                      'Average',
                      'Max speed',
                      'Heart rate',
                      'Cadence',
                      'Power',
                      'Climb',
                      'Altitude',
                      'Grade',
                    ])
                      TextButton(
                        onPressed: fields.contains(f)
                            ? null
                            : () => update(() => fields.add(f)),
                        child: Text(f),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _duration(Duration d) =>
      '${d.inHours.toString().padLeft(2, '0')}:${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';
  (String, String) _metric(String field) {
    final imperial = Runtime.settings.value('imperial', false);
    final factor = imperial ? 0.621371 : 1.0;
    final fresh = session.currentGpsAccuracy != null;
    switch (field) {
      case 'Speed':
        return (
          fresh ? (session.currentSpeed * factor).toStringAsFixed(1) : '—',
          imperial ? 'mph' : 'km/h',
        );
      case 'Distance':
        return (
          (session.totalDistance * factor).toStringAsFixed(2),
          imperial ? 'mi' : 'km',
        );
      case 'Moving time':
        return (_duration(session.movingTime), 'in beweging');
      case 'Elapsed':
        return (_duration(session.elapsedTime), 'totale tijd');
      case 'Average':
        return (
          (session.averageSpeed * factor).toStringAsFixed(1),
          imperial ? 'mph' : 'km/h',
        );
      case 'Max speed':
        return (
          (session.maxSpeed * factor).toStringAsFixed(1),
          imperial ? 'mph' : 'km/h',
        );
      case 'Heart rate':
        return (session.currentHeartRate?.round().toString() ?? '—', 'bpm');
      case 'Cadence':
        return (session.currentCadence?.round().toString() ?? '—', 'rpm');
      case 'Power':
        return (session.currentPower?.round().toString() ?? '—', 'W');
      case 'Climb':
        return (
          fresh
              ? (session.totalElevationGain * (imperial ? 3.28084 : 1))
                    .round()
                    .toString()
              : '—',
          imperial ? 'ft' : 'm · GPS-schatting',
        );
      case 'Altitude':
        return (
          fresh
              ? (session.currentElevation * (imperial ? 3.28084 : 1))
                    .round()
                    .toString()
              : '—',
          imperial ? 'ft' : 'm · GPS',
        );
      default:
        return (
          fresh ? session.currentGrade.toStringAsFixed(1) : '—',
          '% · GPS-schatting',
        );
    }
  }

  double _gridAspect(BoxConstraints size, int count) {
    final columns = size.maxWidth > 700 ? 3 : 2;
    final rows = (count / columns).ceil().clamp(1, 100);
    final height = ((size.maxHeight - 24 - 8 * (rows - 1)) / rows).clamp(
      80.0,
      300.0,
    );
    return ((size.maxWidth - 24 - 8 * (columns - 1)) / columns) / height;
  }

  @override
  Widget build(BuildContext context) {
    final active =
        session.state == RideState.recording ||
        session.state == RideState.paused ||
        session.state == RideState.finished;
    final fields = Runtime.settings.value('minimalRide', false)
        ? ['Speed', 'Distance', 'Elapsed']
        : Runtime.settings.fields(profile);
    final screen = MediaQuery.sizeOf(context);
    final pageSize = screen.width > screen.height
        ? (screen.width > 700 ? 3 : 2)
        : (screen.height < 740 ? 4 : 6);
    final pages = [
      for (var i = 0; i < fields.length; i += pageSize)
        fields.sublist(i, (i + pageSize).clamp(0, fields.length)),
    ];
    return PopScope(
      canPop: !active,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            simulation
                ? 'SIMULATIE · ${session.state.name.toUpperCase()}'
                : session.state.name.toUpperCase(),
          ),
          actions: [
            IconButton(
              tooltip: locked ? 'Ontgrendelen' : 'Aanraakvergrendeling',
              onPressed: () => setState(() => locked = !locked),
              icon: Icon(locked ? Icons.lock : Icons.lock_open),
            ),
            if (!locked)
              IconButton(
                tooltip: 'Gegevensvelden',
                onPressed: _configure,
                icon: const Icon(Icons.dashboard_customize),
              ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (busy) const LinearProgressIndicator(),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(TimeOfDay.now().format(context)),
                    Text(
                      session.currentGpsAccuracy == null
                          ? 'GPS · wacht op fix'
                          : 'GPS ±${session.currentGpsAccuracy!.round()} m',
                    ),
                    Text('${session.trackPoints.length} punten'),
                  ],
                ),
              ),
              if (message != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    message!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.orange),
                  ),
                ),
              Expanded(
                child: AbsorbPointer(
                  absorbing: locked,
                  child: PageView(
                    children: [
                      for (final page in pages)
                        LayoutBuilder(
                          builder: (ctx, size) => GridView.builder(
                            padding: const EdgeInsets.all(12),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: size.maxWidth > 700 ? 3 : 2,
                                  childAspectRatio: _gridAspect(
                                    size,
                                    page.length,
                                  ),
                                  crossAxisSpacing: 8,
                                  mainAxisSpacing: 8,
                                ),
                            itemCount: page.length,
                            itemBuilder: (ctx, i) {
                              final field = page[i];
                              final (value, unit) = _metric(field);
                              return Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        field.toUpperCase(),
                                        style: const TextStyle(
                                          fontSize: 11,
                                          letterSpacing: 1.5,
                                        ),
                                      ),
                                      Expanded(
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            value,
                                            style: TextStyle(
                                              fontSize: field == 'Speed'
                                                  ? 64
                                                  : 42,
                                              fontWeight: FontWeight.w600,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                              color: field == 'Speed'
                                                  ? Theme.of(context)
                                                        .colorScheme
                                                        .primary
                                                  : null,
                                            ),
                                          ),
                                        ),
                                      ),
                                      Text(
                                        unit,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (!locked)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Row(
                    children: [
                      TextButton.icon(
                        onPressed: active ? controller.addDrink : null,
                        icon: const Icon(Icons.water_drop_outlined),
                        label: Text('Drinken $drinks'),
                      ),
                      TextButton.icon(
                        onPressed: active ? controller.addFood : null,
                        icon: const Icon(Icons.restaurant),
                        label: Text('Voeding $foods'),
                      ),
                      const Spacer(),
                      const Text('‹ swipe ›'),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: locked
                    ? const SizedBox(
                        height: 56,
                        child: Center(
                          child: Text(
                            'Vergrendeld · gebruik het slot bovenaan',
                          ),
                        ),
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              key: const ValueKey('ride-start-pause'),
                              onPressed:
                                  busy || session.state == RideState.finished
                                  ? null
                                  : () => _act(
                                      session.isRecording
                                          ? service.pauseRecording
                                          : _start,
                                    ),
                              icon: Icon(
                                session.isRecording
                                    ? Icons.pause
                                    : Icons.play_arrow,
                              ),
                              label: Text(
                                session.isRecording
                                    ? 'PAUZE'
                                    : session.state == RideState.paused
                                    ? 'HERVAT'
                                    : 'START',
                              ),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 60),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              key: const ValueKey('ride-stop'),
                              onPressed: busy || !active ? null : _finish,
                              icon: const Icon(Icons.stop),
                              label: const Text('STOP / OPSLAAN'),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 60),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    controller.removeListener(_changed);
    if (simulation) controller.dispose();
    super.dispose();
  }
}
