import 'package:bike_computer/services/accounts/account_service.dart';
import 'package:bike_computer/services/integrations/backend_strava.dart';
import 'package:bike_computer/features/accounts/account_screen.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:bike_computer/core/runtime.dart';
import 'package:bike_computer/services/integrations/integration_models.dart';
import 'package:bike_computer/services/integrations/sync_scheduler.dart';
import 'package:bike_computer/services/navigation/gpx_route.dart';
import 'package:bike_computer/widgets/route_map.dart';

import 'gpx_exchange_screen.dart';

class ConnectedAppsScreen extends StatelessWidget {
  const ConnectedAppsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Verbonden apps')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Jouw ritten. Jouw keuze.',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 12),
        const Text(
          'Koppel alleen wat je gebruikt. Iedere dienst heeft eigen rechten en mogelijkheden. Uploaden staat standaard uit.',
        ),
        const SizedBox(height: 20),
        Card(
          child: ListTile(
            leading: const Icon(Icons.file_present_outlined),
            title: const Text('GPX-bestanden'),
            subtitle: const Text(
              'Eigen ritten exporteren, routes importeren en zelf uploaden. Geen accountkoppeling nodig.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const GpxExchangeScreen(),
              ),
            ),
          ),
        ),
        ListTile(
          title: const Text('VELO-account'),
          subtitle: const Text('Je account en gekoppelde apps'),
          leading: const Icon(Icons.person_outline),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const AccountScreen()),
          ),
        ),
        const _StravaHubCard(),
        ListTile(
          leading: const Icon(Icons.privacy_tip_outlined),
          title: const Text('Privacy & Synchronisatie'),
          subtitle: const Text(
            'Rechten, gegevenskeuze, geschiedenis en verwijderen',
          ),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => const StravaAccountScreen(),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Beschikbaarheid andere diensten',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const Text(
          'Deze diensten zijn nog niet rechtstreeks beschikbaar in VELO. Je kunt wel GPX-bestanden uitwisselen.',
        ),
        for (final service in IntegrationRegistry.services.skip(1))
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(service.name),
              subtitle: const Text(
                'Nog niet rechtstreeks beschikbaar in VELO.',
              ),
              isThreeLine: false,
              onTap: () => showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(service.name),
                  content: const Text(
                    'Deze dienst is nog niet rechtstreeks gekoppeld aan VELO. Er worden geen gegevens opgehaald of gedeeld. GPX-bestanden kun je via de kaart importeren.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => launchUrl(
                        Uri.parse(service.url),
                        mode: LaunchMode.externalApplication,
                      ),
                      child: const Text('Officiële informatie'),
                    ),
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
    ),
  );
}

class _StravaHubCard extends StatefulWidget {
  const _StravaHubCard();
  @override
  State<_StravaHubCard> createState() => _StravaHubCardState();
}

class _StravaHubCardState extends State<_StravaHubCard> {
  String status = 'Status controleren…', last = 'nog geen';
  Timer? timer;
  @override
  void initState() {
    super.initState();
    _load();
    Runtime.integrations.engine.addListener(_changed);
    timer = Timer.periodic(const Duration(seconds: 10), (_) => _load());
  }

  void _changed() {
    _load();
  }

  Future<void> _load() async {
    try {
      final c = Runtime.integrations,
          a = await c.strava.service.account(),
          s = await c.strava.repository.state('strava');
      final pending = await c.strava.service.store.read('strava-state');
      if (mounted) {
        setState(() {
          status = c.engine.busy
              ? 'Synchroniseren…'
              : pending != null
              ? 'Verbinden…'
              : a == null
              ? 'Niet verbonden'
              : s['status'] ?? 'Verbonden';
          last = s['lastSuccess'] ?? 'nog geen';
        });
      }
    } catch (_) {
      if (mounted) setState(() => status = 'Status niet beschikbaar');
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.all(20),
      leading: const Icon(Icons.sync, size: 32),
      title: const Text('Strava'),
      subtitle: Text(
        'Activiteiten, routes en ritten delen\n$status\nLaatste synchronisatie: $last',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const StravaAccountScreen()),
        );
        await _load();
      },
    ),
  );
  @override
  void dispose() {
    timer?.cancel();
    Runtime.integrations.engine.removeListener(_changed);
    super.dispose();
  }
}

class StravaAccountScreen extends StatefulWidget {
  final IntegrationCoordinator? coordinator;
  const StravaAccountScreen({super.key, this.coordinator});
  @override
  State<StravaAccountScreen> createState() => _StravaAccountScreenState();
}

class _StravaAccountScreenState extends State<StravaAccountScreen> {
  late final coordinator = widget.coordinator ?? Runtime.integrations;
  late final provider = coordinator.strava,
      service = provider.service,
      repo = provider.repository;
  bool configured = false;
  SyncPreferences preferences = const SyncPreferences();
  Map<String, dynamic>? account;
  Map<String, dynamic> state = {};
  List<Map<String, dynamic>> history = [];
  Map<String, String> jobs = {};
  bool busy = false,
      loading = true,
      privateData = false,
      connecting = false,
      _reading = false;
  String? message;
  Timer? refresh;
  @override
  void initState() {
    super.initState();
    _load(initial: true);
    coordinator.engine.addListener(_changed);
    refresh = Timer.periodic(const Duration(seconds: 10), (_) => _load());
  }

  void _changed() {
    _load();
  }

  Future<void> _load({bool initial = false}) async {
    if (_reading) return;
    _reading = true;
    try {
      await provider.cache.expire();
      if (service is BackendStravaService) {
        await (service as BackendStravaService).refreshStatus();
      }
      if (service is BackendStravaService) {
        configured =
            (await (service as BackendStravaService)
                .information())['configured'] ==
            true;
      }
      final a = await service.account(),
          p = await repo.preferences('strava'),
          s = await repo.state('strava');
      final h =
          (await Runtime.database.documents('sync-history')).values
              .map((v) => jsonDecode(v) as Map<String, dynamic>)
              .where((r) => r['provider'] == 'strava')
              .toList()
            ..sort((a, b) => b['date'].compareTo(a['date']));
      final j = await Runtime.database.documents('sync');
      if (initial) {
        privateData = await service.store.read('strava-private') == 'true';
      }
      final pending = await service.store.read('strava-state');
      if (mounted) {
        setState(() {
          if (s['error'] != null || (a != null && account == null)) {
            message = null;
          }
          account = a;
          preferences = p;
          state = s;
          history = h;
          jobs = j;
          loading = false;
          connecting = pending != null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          message =
              'Accountstatus kon niet veilig worden gelezen. Probeer opnieuw.';
        });
      }
    } finally {
      _reading = false;
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    coordinator.oauthMessage = null;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(
          () => message =
              e is AccountFailure ||
                  e is IntegrationFailure ||
                  e is ArgumentError ||
                  e is FormatException
              ? e.toString()
              : 'De actie is niet voltooid. Controleer verbinding en configuratie.',
        );
      }
    } finally {
      await _load();
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> _confirm(String title, String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuleren'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Bevestigen'),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> _change(String key, bool value) => _run(() async {
    if (key == 'uploads' &&
        value &&
        !await _confirm(
          'Ritten delen met Strava?',
          'Handmatig gekozen of expliciet automatisch geselecteerde ritten worden als GPX inclusief GPS-spoor en tijdstippen naar Strava verstuurd. Je geeft hiervoor toestemming in Strava.',
        )) {
      return;
    }
    preferences = preferences.withValue(key, value);
    await repo.savePreferences('strava', preferences);
    if (service is BackendStravaService && await provider.connected()) {
      await (service as BackendStravaService).accounts.request(
        'PUT',
        '/api/v1/integrations/strava/preferences',
        body: {
          for (final k in [
            'enabled',
            'automatic',
            'activities',
            'routes',
            'uploads',
          ])
            k: preferences.toJson()[k],
        },
      );
    }
    await coordinator.schedule();
  });
  Future<void> _connect() => _run(() async {
    final requested = <String>[
      if (preferences.activities)
        privateData ? 'activity:read_all' : 'activity:read',
      if (preferences.routes) privateData ? 'read_all' : 'read',
      if (preferences.uploads) 'activity:write',
    ];
    if (requested.isEmpty) {
      throw const IntegrationFailure('Kies minstens één gegevenscategorie.');
    }
    await service.store.write('strava-private', privateData.toString());
    await service.authorize(
      await service.store.read('strava-base') ?? '',
      await service.store.read('strava-client-id') ?? '',
      scopes: requested,
    );
    message = 'Geef toestemming in Strava en keer daarna terug naar VELO.';
  });
  String get status => coordinator.engine.busy
      ? 'Synchroniseren…'
      : busy
      ? 'Bezig…'
      : connecting
      ? 'Verbinden…'
      : account == null
      ? 'Niet verbonden'
      : state['status'] ?? 'Verbonden';
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Strava · account'),
      actions: [
        IconButton(
          tooltip: 'Status vernieuwen',
          onPressed: () => _load(),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Compatible with Strava',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(status, key: const ValueKey('strava-status')),
                      if (account?['athlete'] != null)
                        Text(
                          '${account!['athlete']['firstname'] ?? ''} ${account!['athlete']['lastname'] ?? ''} · account ${account!['athlete']['id']}',
                        ),
                      Text(
                        'Laatste geslaagde synchronisatie: ${state['lastSuccess'] ?? 'nog geen'}',
                      ),
                      if (state['next'] != null)
                        Text('Volgende poging vanaf: ${state['next']}'),
                      if (account != null)
                        Text(
                          'Verleende rechten: ${account!['scope'] ?? 'onbekend; verbind opnieuw'}',
                        ),
                      if (busy || coordinator.engine.busy)
                        const LinearProgressIndicator(),
                    ],
                  ),
                ),
              ),
              if (message != null ||
                  state['error'] != null ||
                  coordinator.oauthMessage != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    message ?? state['error'] ?? coordinator.oauthMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (account == null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    Runtime.accounts.user == null &&
                            service is BackendStravaService
                        ? 'Meld je aan bij VELO om Strava te verbinden.'
                        : service is BackendStravaService && !configured
                        ? 'Strava is momenteel niet beschikbaar in VELO. Probeer later opnieuw.'
                        : 'Verbind je Strava-account. Jij kiest welke gegevens je deelt.',
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                'Privacy & Synchronisatie',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Text(
                'Strava-gegevens zijn een afzonderlijke persoonlijke cache (maximaal 24 uur). Ze worden niet gecombineerd met lokale statistieken, niet in back-ups opgenomen en niet aan AI of andere diensten doorgegeven. Inkomende gegevens zijn geen ruwe sensormetingen.',
              ),
              for (final entry in <(String, String, String)>[
                (
                  'enabled',
                  'Gegevensuitwisseling toestaan',
                  'Uit schakelt alle synchronisatie uit.',
                ),
                (
                  'activities',
                  'Activiteiten ophalen',
                  'Je recente activiteiten verschijnen automatisch in VELO.',
                ),
                (
                  'routes',
                  'Routes ophalen',
                  'Je recente routes gebruiken op de kaart.',
                ),
                (
                  'uploads',
                  'Ritten naar Strava versturen',
                  'Alleen geselecteerde eigen ritten; geen geïmporteerde activiteiten.',
                ),
                (
                  'automatic',
                  'Automatisch synchroniseren',
                  'Je gegevens blijven op de achtergrond bijgewerkt.',
                ),
                (
                  'onOpen',
                  'Bij openen van de app',
                  'Alleen wanneer automatisch synchroniseren aanstaat.',
                ),
                (
                  'afterRide',
                  'Na een opgeslagen rit',
                  'Voegt de nieuwe eigen rit toe als uploaden én automatisch aanstaan.',
                ),
                (
                  'onNetwork',
                  'Bij netwerkherstel',
                  'Alleen wanneer automatisch synchroniseren aanstaat.',
                ),
                (
                  'wifiOnly',
                  'Alleen via wifi',
                  'Geldt ook voor handmatig synchroniseren.',
                ),
              ])
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(entry.$2),
                  subtitle: Text(entry.$3),
                  value: preferences.toJson()[entry.$1],
                  onChanged: busy || coordinator.engine.busy
                      ? null
                      : (v) => _change(entry.$1, v),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ook privéactiviteiten / privéroutes'),
                subtitle: const Text(
                  'Geef opnieuw toestemming om ook deze gegevens op te halen.',
                ),
                value: privateData,
                onChanged: busy ? null : (v) => setState(() => privateData = v),
              ),
              if (account == null &&
                  (service is! BackendStravaService ||
                      (configured && Runtime.accounts.user != null)))
                Semantics(
                  button: true,
                  label: 'Connect with Strava',
                  child: InkWell(
                    key: const ValueKey('connect-strava'),
                    onTap: busy || coordinator.engine.busy ? null : _connect,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Image.asset(
                        'assets/images/strava-connect.png',
                        height: 48,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                )
              else if (account != null)
                FilledButton(
                  key: const ValueKey('connect-strava'),
                  onPressed: busy || coordinator.engine.busy ? null : _connect,
                  child: Text(
                    account == null
                        ? 'Connect with Strava'
                        : 'Toestemming aanpassen',
                  ),
                ),
              if (account != null) ...[
                OutlinedButton(
                  onPressed: busy || coordinator.engine.busy
                      ? null
                      : () => _run(() async {
                          await coordinator.engine.run();
                          message = 'Bekijk de actuele status en geschiedenis hieronder.';
                        }),
                  child: const Text('Synchroniseer nu / opnieuw proberen'),
                ),
                TextButton(
                  onPressed: () => launchUrl(
                    Uri.parse('https://www.strava.com/settings/apps'),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: const Text('Account beheren bij Strava'),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => _run(() async {
                          if (!await _confirm(
                            'Opnieuw synchroniseren?',
                            'De tijdelijke Strava-cache en cursor worden gewist. Eigen opgenomen ritten blijven behouden.',
                          )) {
                            return;
                          }
                          await provider.cache.expire(all: true);
                          await repo.update('strava', {
                            'cursor': null,
                            'fullRefresh': null,
                          });
                          await coordinator.engine.run(
                            trigger: 'reset',
                            reset: true,
                          );
                        }),
                  child: const Text('Synchronisatiegegevens opnieuw ophalen'),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => _run(() async {
                          if (!await _confirm(
                            'Geïmporteerde gegevens verwijderen?',
                            'Verwijdert alleen de tijdelijke Strava-activiteiten en -routes op dit toestel.',
                          )) {
                            return;
                          }
                          await provider.cache.expire(all: true);
                        }),
                  child: const Text('Lokale Strava-cache verwijderen'),
                ),
                TextButton(
                  onPressed: busy || coordinator.engine.busy
                      ? null
                      : () => _run(() async {
                          if (!await _confirm(
                            'Strava ontkoppelen?',
                            'Ontkoppelt Strava en verwijdert de opgehaalde Strava-gegevens. Je eigen ritten blijven bewaard.',
                          )) {
                            return;
                          }
                          try {
                            await provider.disconnect();
                          } finally {
                            await coordinator.schedule();
                          }
                          message = 'Account ontkoppeld.';
                        }),
                  child: const Text('Ontkoppelen'),
                ),
                OutlinedButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const StravaDataScreen(),
                    ),
                  ),
                  child: const Text('Activiteiten & routes bekijken'),
                ),
                const SizedBox(height: 20),
                Text(
                  'Eigen rit selecteren voor upload',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                FutureBuilder(
                  future: Runtime.database.getAllRides(),
                  builder: (context, snapshot) => Column(
                    children: [
                      if ((snapshot.data ?? []).isEmpty)
                        const Text('Nog geen eigen opgenomen ritten.'),
                      for (final ride in snapshot.data ?? [])
                        ListTile(
                          title: Text('${ride.startTime ?? 'Geen starttijd'}'),
                          subtitle: Text(
                            '${ride.totalDistance.toStringAsFixed(1)} km · lokaal opgenomen',
                          ),
                          trailing: TextButton(
                            onPressed: !preferences.uploads || busy
                                ? null
                                : () => _run(() async {
                                    if (!(await service.scopes()).contains(
                                      'activity:write',
                                    )) {
                                      throw const IntegrationFailure(
                                        'Verbind opnieuw met uploadrechten.',
                                      );
                                    }
                                    await service.enqueue(ride.rideId);
                                    message = 'Rit staat in de uploadwachtrij. Kies Synchroniseer nu of activeer automatische synchronisatie.';
                                  }),
                            child: const Text('In wachtrij'),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Text(
                'Uitgaande wachtrij',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (jobs.isEmpty) const Text('Geen uitgaande acties.'),
              for (final row in jobs.entries)
                Builder(
                  builder: (ctx) {
                    final j = jsonDecode(row.value);
                    return ListTile(
                      title: Text(row.key),
                      subtitle: Text('${j['status']} · ${j['error'] ?? ''}'),
                      trailing:
                          [
                            'failed',
                            'needs_review',
                            'unknown',
                          ].contains(j['status'])
                          ? TextButton(
                              onPressed: () => _run(() async {
                                if (!await _confirm(
                                  'Deze upload opnieuw proberen?',
                                  'Controleer eerst bij Strava of de rit al bestaat. Onzekere uploads worden niet automatisch herhaald.',
                                )) {
                                  return;
                                }
                                if (service is BackendStravaService) {
                                  await (service as BackendStravaService)
                                      .accounts
                                      .request(
                                        'POST',
                                        '/api/v1/jobs/${j['job_id']}/retry',
                                        body: {'confirmed_no_duplicate': true},
                                      );
                                } else {
                                  await Runtime.database.putDocument(
                                    'sync',
                                    row.key,
                                    jsonEncode({
                                      ...j,
                                      'status': 'pending',
                                      'next': 0,
                                    }),
                                  );
                                }
                              }),
                              child: const Text('Opnieuw'),
                            )
                          : null,
                    );
                  },
                ),
              Text(
                'Synchronisatiegeschiedenis',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (history.isEmpty)
                const Text('Nog geen synchronisaties uitgevoerd.'),
              for (final row in history)
                ListTile(
                  title: Text(row['message']),
                  subtitle: Text(
                    '${row['date']} · ${row['trigger']} · ${row['status']}',
                  ),
                ),
            ],
          ),
  );
  @override
  void dispose() {
    refresh?.cancel();
    coordinator.engine.removeListener(_changed);
    super.dispose();
  }
}

class StravaDataScreen extends StatefulWidget {
  const StravaDataScreen({super.key});
  @override
  State<StravaDataScreen> createState() => _StravaDataScreenState();
}

class _StravaDataScreenState extends State<StravaDataScreen> {
  final provider = Runtime.integrations.strava;
  List<Map<String, dynamic>> activities = [];
  Map<String, String> routes = {};
  String? error;
  bool busy = false;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    _load();
    timer = Timer.periodic(const Duration(minutes: 1), (_) => _load());
  }

  Future<void> _load() async {
    await provider.cache.expire();
    final a = (await Runtime.database.documents('strava-activities')).values
            .map((v) => jsonDecode(v) as Map<String, dynamic>)
            .toList(),
        r = await Runtime.database.documents('routes');
    if (mounted) {
      setState(() {
        activities = a;
        routes = Map.fromEntries(
          r.entries.where((e) => e.key.startsWith('strava:')),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Afkomstig van Strava')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Tijdelijke gegevens van je eigen Strava-account. Afzonderlijk van lokale ritstatistieken en trainingsresultaten. De cache verloopt binnen 24 uur.',
        ),
        if (error != null) Text(error!),
        if (busy) const LinearProgressIndicator(),
        if (activities.isEmpty)
          const ListTile(title: Text('Geen gesynchroniseerde activiteiten.')),
        for (final row in activities)
          Builder(
            builder: (context) {
              final a = row['data'];
              return Card(
                child: ListTile(
                  title: Text(a['name'] ?? 'Activiteit zonder naam'),
                  subtitle: Text(
                    '${a['distance'] / 1000} km · ${a['moving_time']} s in beweging\nStrava · gesynchroniseerd ${row['synced']}',
                  ),
                  onTap: busy
                      ? null
                      : () async {
                          setState(() => busy = true);
                          try {
                            final d = await provider.details(a['id']);
                            if (!context.mounted) return;
                            await showDialog<void>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: Text(d['name'] ?? 'Strava-activiteit'),
                                content: Text(
                                  'Bron: Strava\nAfstand: ${d['distance'] / 1000} km\nBewegingstijd: ${d['moving_time']} s\nTotale tijd: ${d['elapsed_time']} s\nHoogtemeters: ${d['total_elevation_gain'] ?? 'niet beschikbaar'}\nHartslag: ${d['average_heartrate'] ?? 'niet beschikbaar'}\nVermogen: ${d['average_watts'] ?? 'niet beschikbaar'}',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => launchUrl(
                                      Uri.parse(
                                        'https://www.strava.com/activities/${a['id']}',
                                      ),
                                      mode: LaunchMode.externalApplication,
                                    ),
                                    child: const Text('View on Strava'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text('Sluiten'),
                                  ),
                                ],
                              ),
                            );
                          } catch (e) {
                            if (mounted) setState(() => error = e.toString());
                          } finally {
                            if (mounted) setState(() => busy = false);
                            await _load();
                          }
                        },
                ),
              );
            },
          ),
        const SizedBox(height: 20),
        Text('Routes', style: Theme.of(context).textTheme.titleLarge),
        if (routes.isEmpty) const Text('Geen gesynchroniseerde routes.'),
        for (final row in routes.entries)
          ListTile(
            title: Text(NavRoute.decode(row.value).name),
            subtitle: const Text(
              'Strava · tijdelijk lokaal · ook in Kaart → Lokale routes',
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('Strava-route')),
                  body: RouteMap(route: NavRoute.decode(row.value)),
                ),
              ),
            ),
          ),
      ],
    ),
  );
  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }
}
