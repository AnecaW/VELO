import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:bike_computer/core/runtime.dart';
import 'package:bike_computer/services/training/training_generator.dart';
import 'package:bike_computer/models/sensor_models.dart';

class TrainingScreen extends StatefulWidget {
  final bool history;
  const TrainingScreen({super.key, this.history = false});
  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  final store = TrainingStore(Runtime.database);
  List<TrainingPlan> plans = [];
  TrainingProfile profile = const TrainingProfile();
  String? error;
  int tab = 0;
  @override
  void initState() {
    super.initState();
    tab = widget.history ? 2 : 0;
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await store.plans(), s = await store.loadProfile();
      if (mounted) {
        setState(() {
          plans = p;
          profile = s;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> _profile() async {
    final result = await Navigator.push<TrainingProfile>(
      context,
      MaterialPageRoute(
        builder: (_) => TrainingProfileScreen(initial: profile),
      ),
    );
    if (result != null) {
      await store.profile(result);
      if (mounted) setState(() => profile = result);
    }
  }

  Future<void> _generate() async {
    try {
      final next = await LocalTrainingGenerator().generate(profile);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => PlanScreen(plan: next)),
      );
      await _load();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> _week() async {
    try {
      profile.validate();
      for (var i = 0, added = 0; i < 7 && added < profile.days; i++) {
        final date = DateTime.now().add(Duration(days: i));
        if (!profile.weekdays.contains(date.weekday)) continue;
        final p = await LocalTrainingGenerator().generate(profile);
        await store.save(
          p.copy(scheduled: date.toIso8601String().substring(0, 10)),
        );
        added++;
      }
      await _load();
      if (mounted) setState(() => tab = 1);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Training'),
      actions: [
        IconButton(
          tooltip: 'Trainingsprofiel',
          onPressed: _profile,
          icon: const Icon(Icons.tune),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Jouw volgende stap.',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Lokale trainingsadviezen. Jouw resultaten ontstaan pas tijdens een uitvoering.',
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${profile.goal} · ${profile.minutes} min',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  '${profile.level} · ${profile.days} dagen/week · ${profile.ftp == null ? 'zonder FTP' : 'FTP ${profile.ftp!.round()} W'}',
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const ValueKey('generate-workout'),
                  onPressed: _generate,
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: const Text('Training samenstellen'),
                ),
                TextButton(
                  onPressed: _profile,
                  child: const Text('Voorkeuren wijzigen'),
                ),
              ],
            ),
          ),
        ),
        if (Runtime.workout.plan != null)
          ListenableBuilder(
            listenable: Runtime.workout,
            builder: (context, _) => ListTile(
              leading: const Icon(Icons.play_circle_outline),
              title: Text(Runtime.workout.plan!.name),
              subtitle: Text(
                Runtime.workout.complete
                    ? 'Laatste uitvoering'
                    : 'Actieve training · ${Runtime.workout.remaining} s',
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const TrainingExecutionScreen(),
                ),
              ),
            ),
          ),
        const SizedBox(height: 16),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('Bibliotheek')),
            ButtonSegment(value: 1, label: Text('Week')),
            ButtonSegment(value: 2, label: Text('Resultaten')),
          ],
          selected: {tab},
          onSelectionChanged: (s) => setState(() => tab = s.first),
        ),
        const SizedBox(height: 16),
        if (error != null)
          Text(error!, style: const TextStyle(color: Colors.orange)),
        if (tab == 0) ...[
          if (plans.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Nog geen trainingen. Stel je eerste training samen en bewaar die.',
              ),
            ),
          for (final plan in plans)
            Card(
              child: ListTile(
                title: Text(plan.name),
                subtitle: Text('${plan.seconds ~/ 60} min · ${plan.goal}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => PlanScreen(plan: plan),
                    ),
                  );
                  await _load();
                },
              ),
            ),
        ],
        if (tab == 1) ...[
          OutlinedButton(
            onPressed: _week,
            child: const Text('Week samenstellen op mijn trainingsdagen'),
          ),
          for (var i = 0; i < 7; i++)
            Builder(
              builder: (context) {
                final date = DateTime.now().add(Duration(days: i));
                final key =
                    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                final scheduled = plans.where((p) => p.scheduled == key);
                return Card(
                  child: Column(
                    children: [
                      ListTile(
                        title: Text(
                          '${['Ma', 'Di', 'Wo', 'Do', 'Vr', 'Za', 'Zo'][date.weekday - 1]} ${date.day}/${date.month}',
                        ),
                        subtitle: Text(
                          scheduled.isEmpty
                              ? 'Rustdag / vrij'
                              : '${scheduled.length} training(en)',
                        ),
                      ),
                      for (final p in scheduled)
                        ListTile(
                          title: Text(p.name),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => PlanScreen(plan: p),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
        ],
        if (tab == 2)
          FutureBuilder(
            future: Runtime.database.documents('training-results'),
            builder: (context, snapshot) {
              final rows = (snapshot.data ?? {}).values
                  .map((r) => jsonDecode(r) as Map<String, dynamic>)
                  .toList()
                  .reversed
                  .toList();
              return Column(
                children: [
                  if (rows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Nog geen uitgevoerde trainingen.'),
                    ),
                  for (final r in rows)
                    Card(
                      child: ListTile(
                        title: Text(r['name']),
                        subtitle: Text(
                          '${r['started'].toString().substring(0, 10)} · ${r['seconds']} s · ${r['status'] == 'active' ? 'Onderbroken of nog actief' : r['status']}',
                        ),
                        onTap: () => showDialog<void>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text(r['name']),
                            content: SingleChildScrollView(
                              child: Text(
                                'Werkelijke uitvoering: ${r['seconds']} s\nStatus: ${r['status']}\nGekoppelde rit: ${r['rideId'] ?? 'geen'}\nActuele sensormetingen opgeslagen: ${(r['measurements'] as List).length}',
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
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    ),
  );
}

class TrainingProfileScreen extends StatefulWidget {
  final TrainingProfile initial;
  const TrainingProfileScreen({super.key, required this.initial});
  @override
  State<TrainingProfileScreen> createState() => _TrainingProfileScreenState();
}

class _TrainingProfileScreenState extends State<TrainingProfileScreen> {
  late String goal, level, environment, preference;
  late double minutes, intensity;
  late int days;
  late bool power, hr;
  late Set<int> weekdays;
  final ftp = TextEditingController(),
      low = TextEditingController(),
      high = TextEditingController(),
      custom = TextEditingController();
  String? error;
  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    goal = p.goal;
    level = p.level;
    environment = p.environment;
    preference = p.preference;
    minutes = p.minutes.toDouble();
    intensity = p.intensity.toDouble();
    days = p.days;
    power = p.powerSensor;
    hr = p.heartSensor;
    weekdays = p.weekdays.toSet();
    ftp.text = p.ftp?.toStringAsFixed(0) ?? '';
    low.text = p.hrLow?.toString() ?? '';
    high.text = p.hrHigh?.toString() ?? '';
    custom.text = p.custom;
  }

  Widget choice(
    String title,
    String value,
    List<String> choices,
    ValueChanged<String> changed,
  ) => DropdownButtonFormField<String>(
    initialValue: value,
    decoration: InputDecoration(labelText: title),
    items: choices
        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
        .toList(),
    onChanged: (v) => setState(() => changed(v!)),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Trainingsprofiel')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        choice('Doel', goal, [
          'Conditie',
          'Uithoudingsvermogen',
          'Langdurig vermogen',
          'Klimmen',
          'Intervallen',
          'Herstel',
          'Cadans',
          'Tempo',
          'Lange fietstocht',
          'Persoonlijk',
        ], (v) => goal = v),
        const SizedBox(height: 12),
        if (goal == 'Persoonlijk')
          TextField(
            controller: custom,
            decoration: const InputDecoration(labelText: 'Eigen doel'),
          ),
        choice('Ervaring', level, [
          'Beginner',
          'Gevorderd',
          'Ervaren',
        ], (v) => level = v),
        const SizedBox(height: 12),
        choice('Omgeving', environment, [
          'Buiten',
          'Indoor',
        ], (v) => environment = v),
        const SizedBox(height: 12),
        choice('Voorkeur', preference, [
          'Duur',
          'Intervallen',
          'Herstel',
        ], (v) => preference = v),
        ListTile(title: Text('${minutes.round()} minuten')),
        Slider(
          value: minutes,
          min: 10,
          max: 240,
          divisions: 46,
          onChanged: (v) => setState(() => minutes = v),
        ),
        ListTile(title: Text('Gewenste intensiteit ${intensity.round()}/10')),
        Slider(
          value: intensity,
          min: 1,
          max: 9,
          divisions: 8,
          onChanged: (v) => setState(() => intensity = v),
        ),
        DropdownButtonFormField<int>(
          initialValue: days,
          decoration: const InputDecoration(labelText: 'Trainingsdagen/week'),
          items: [
            for (var i = 1; i <= 7; i++)
              DropdownMenuItem(value: i, child: Text('$i')),
          ],
          onChanged: (v) => setState(() => days = v!),
        ),
        Wrap(
          spacing: 4,
          children: [
            for (var i = 1; i <= 7; i++)
              FilterChip(
                label: Text(['Ma', 'Di', 'Wo', 'Do', 'Vr', 'Za', 'Zo'][i - 1]),
                selected: weekdays.contains(i),
                onSelected: (v) => setState(() {
                  if (v) {
                    weekdays.add(i);
                  } else {
                    weekdays.remove(i);
                  }
                }),
              ),
          ],
        ),
        SwitchListTile(
          title: const Text('Vermogensmeter beschikbaar'),
          value: power,
          onChanged: (v) => setState(() => power = v),
        ),
        TextField(
          controller: ftp,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Eigen FTP in W · optioneel, nooit geraden',
          ),
        ),
        SwitchListTile(
          title: const Text('Hartslagmeter beschikbaar'),
          value: hr,
          onChanged: (v) => setState(() => hr = v),
        ),
        if (hr) ...[
          TextField(
            controller: low,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Ingestelde trainingszone · ondergrens bpm',
            ),
          ),
          TextField(
            controller: high,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Bovengrens bpm'),
          ),
        ],
        if (error != null)
          Text(error!, style: const TextStyle(color: Colors.orange)),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () {
            try {
              final p = TrainingProfile(
                goal: goal,
                level: level,
                environment: environment,
                preference: preference,
                custom: custom.text,
                minutes: minutes.round(),
                days: days,
                intensity: intensity.round(),
                weekdays: weekdays.toList(),
                ftp: ftp.text.trim().isEmpty ? null : double.parse(ftp.text),
                powerSensor: power,
                heartSensor: hr,
                hrLow: int.tryParse(low.text),
                hrHigh: int.tryParse(high.text),
              );
              p.validate();
              Navigator.pop(context, p);
            } catch (e) {
              setState(() => error = e.toString());
            }
          },
          child: const Text('Profiel opslaan'),
        ),
      ],
    ),
  );
  @override
  void dispose() {
    ftp.dispose();
    low.dispose();
    high.dispose();
    custom.dispose();
    super.dispose();
  }
}

class PlanScreen extends StatefulWidget {
  final TrainingPlan plan;
  const PlanScreen({super.key, required this.plan});
  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  late TrainingPlan plan;
  String? message;
  @override
  void initState() {
    super.initState();
    plan = widget.plan;
  }

  Future<void> run(Future<void> Function() fn) async {
    try {
      await fn();
    } catch (e) {
      if (mounted) setState(() => message = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Trainingsadvies'),
      actions: [
        IconButton(
          tooltip: 'Verwijderen',
          onPressed: () => run(() async {
            final yes = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Training verwijderen?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Annuleren'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Verwijderen'),
                  ),
                ],
              ),
            );
            if (yes == true) {
              await Runtime.database.removeDocument('training-plans', plan.id);
              if (context.mounted) Navigator.pop(context);
            }
          }),
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextFormField(
          initialValue: plan.name,
          decoration: const InputDecoration(labelText: 'Naam'),
          onChanged: (v) => plan = plan.copy(name: v),
        ),
        const SizedBox(height: 16),
        Text(
          '${plan.seconds ~/ 60} min ${plan.seconds % 60} s · ${plan.goal}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Text(
          plan.ftp == null
              ? 'Geen FTP ingesteld: volg ervaren inspanning (RPE).'
              : 'Wattagedoelen gebruiken je eigen FTP van ${plan.ftp!.round()} W.',
        ),
        if (plan.estimatedTss != null)
          Text(
            'Geschatte belasting: ${plan.estimatedTss!.round()} TSS (doel, geen prestatiemeting)',
          ),
        for (var i = 0; i < plan.steps.length; i++)
          Card(
            child: ListTile(
              title: Text(plan.steps[i].name),
              subtitle: Text(
                '${plan.steps[i].seconds} s · RPE ${plan.steps[i].rpe}/10${plan.steps[i].ftpFraction == null ? '' : ' · ${(plan.steps[i].ftpFraction! * plan.ftp!).round()} W'}${plan.steps[i].cadence == null ? '' : ' · ${plan.steps[i].cadence} rpm'}',
              ),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _edit(i),
            ),
          ),
        if (message != null)
          Text(message!, style: const TextStyle(color: Colors.orange)),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => run(() async {
            await TrainingStore(Runtime.database).save(plan);
            if (mounted) setState(() => message = 'Training opgeslagen');
          }),
          child: const Text('Training opslaan'),
        ),
        OutlinedButton(
          onPressed: () => run(() async {
            await TrainingStore(Runtime.database).save(plan);
            await Runtime.workout.start(plan, ride: Runtime.ride.session.id);
            if (context.mounted) {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const TrainingExecutionScreen(),
                ),
              );
            }
          }),
          child: const Text('Training starten'),
        ),
        Wrap(
          children: [
            TextButton(
              onPressed: () => run(() async {
                final yes = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Zelf als voltooid markeren?'),
                    content: const Text(
                      'Dit is jouw eigen bevestiging. Er worden geen uitvoeringstijd of sensormetingen verzonnen.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Annuleren'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Voltooid markeren'),
                      ),
                    ],
                  ),
                );
                if (yes != true) return;
                plan.validate();
                final now = DateTime.now(),
                    id = 'result-${DateTime.now().microsecondsSinceEpoch}';
                await Runtime.database.putDocument(
                  'training-results',
                  id,
                  jsonEncode({
                    'id': id,
                    'planId': plan.id,
                    'plan': plan.encode(),
                    'name': plan.name,
                    'started': now.toIso8601String(),
                    'status': 'Zelf gemeld voltooid · geen metingen',
                    'seconds': 0,
                    'measurements': <dynamic>[],
                    'rideId': Runtime.ride.session.id,
                  }),
                );
                if (mounted) {
                  setState(() => message = 'Als zelf gemeld voltooid bewaard');
                }
              }),
              child: const Text('Voltooid markeren'),
            ),
            TextButton(
              onPressed: () => run(() async {
                final d = await showDatePicker(
                  context: context,
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now().add(const Duration(days: 730)),
                );
                if (d != null) {
                  plan = plan.copy(
                    scheduled: d.toIso8601String().substring(0, 10),
                  );
                  await TrainingStore(Runtime.database).save(plan);
                  if (mounted) {
                    setState(() => message = 'Gepland op ${plan.scheduled}');
                  }
                }
              }),
              child: const Text('Inplannen'),
            ),
            TextButton(
              onPressed: () => run(() async {
                final copy = plan.copy(
                  id: 'training-${DateTime.now().microsecondsSinceEpoch}',
                  name: '${plan.name} · kopie',
                );
                await TrainingStore(Runtime.database).save(copy);
                if (mounted) setState(() => message = 'Kopie opgeslagen');
              }),
              child: const Text('Dupliceren'),
            ),
          ],
        ),
      ],
    ),
  );
  Future<void> _edit(int i) async {
    final s = plan.steps[i],
        seconds = TextEditingController(text: plan.steps[i].seconds.toString()),
        rpe = TextEditingController(text: plan.steps[i].rpe.toString());
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: seconds,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Seconden'),
            ),
            TextField(
              controller: rpe,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'RPE 1–10'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () {
              final duration = int.tryParse(seconds.text),
                  effort = int.tryParse(rpe.text);
              if (duration == null ||
                  effort == null ||
                  duration <= 0 ||
                  effort < 1 ||
                  effort > 10) {
                return;
              }
              setState(() {
                final steps = [...plan.steps];
                steps[i] = TrainingStep(
                  s.name,
                  duration,
                  effort,
                  ftpFraction: s.ftpFraction,
                  hrLow: s.hrLow,
                  hrHigh: s.hrHigh,
                  cadence: s.cadence,
                );
                plan = plan.copy(steps: steps);
              });
              Navigator.pop(ctx);
            },
            child: const Text('Wijzigen'),
          ),
        ],
      ),
    );
    seconds.dispose();
    rpe.dispose();
  }
}

class TrainingExecutionScreen extends StatelessWidget {
  const TrainingExecutionScreen({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Runtime.workout,
    builder: (context, _) {
      final r = Runtime.workout, s = r.current;
      return Scaffold(
        appBar: AppBar(title: const Text('Training uitvoeren')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              r.plan?.name ?? 'Geen actieve training',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 24),
            Text(
              s?.name ?? 'Uitvoering beëindigd',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              '${r.remaining ~/ 60}:${(r.remaining % 60).toString().padLeft(2, '0')}',
              style: Theme.of(context).textTheme.displayLarge,
            ),
            if (s != null) ...[
              Text(
                'Doel RPE ${s.rpe}/10${s.ftpFraction == null ? '' : ' · ${(s.ftpFraction! * r.plan!.ftp!).round()} W'}',
              ),
              if (s.hrLow != null)
                Text('Ingestelde hartslagzone ${s.hrLow}–${s.hrHigh} bpm'),
              if (s.cadence != null) Text('Cadansdoel ${s.cadence} rpm'),
              if (r.index + 1 < r.plan!.steps.length)
                Text('Hierna: ${r.plan!.steps[r.index + 1].name}'),
            ],
            Text(
              'Vermogen: ${r.reading(SensorType.power)?.value.round().toString() ?? '—'} W',
            ),
            Text(
              'Hartslag: ${r.reading(SensorType.heartRate)?.value.round().toString() ?? '—'} bpm',
            ),
            if (s?.ftpFraction != null && r.reading(SensorType.power) != null)
              Text(
                'Verschil met vermogensdoel: ${(r.reading(SensorType.power)!.value - s!.ftpFraction! * r.plan!.ftp!).round()} W',
              ),
            Text(
              'Cadans: ${r.reading(SensorType.cadence)?.value.round().toString() ?? '—'} rpm',
            ),
            Text('Actieve uitvoering: ${r.activeSeconds} s'),
            if (r.error != null) Text(r.error!),
            if (!r.complete && r.plan != null) ...[
              FilledButton(
                onPressed: r.toggle,
                child: Text(r.paused ? 'Hervatten' : 'Pauzeren'),
              ),
              OutlinedButton(
                onPressed: r.skip,
                child: const Text('Stap overslaan'),
              ),
              TextButton(
                onPressed: () async {
                  await r.stop();
                },
                child: const Text('Training beëindigen'),
              ),
            ],
            const Text(
              'Sensorwaarden worden alleen bij actuele metingen opgeslagen. De training blijft lopen wanneer je andere schermen opent.',
            ),
          ],
        ),
      );
    },
  );
}
