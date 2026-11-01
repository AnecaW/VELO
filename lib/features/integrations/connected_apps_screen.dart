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
            title: const Text('GPX uitwisselen Â· zonder server'),
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
          subtitle: const Text('Aanmelden bij je eigen server'),
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
          'Dit zijn geen gekoppelde accounts. Alleen geÃ¯mplementeerde en geconfigureerde adapters kunnen verbinding maken.',
        ),
        for (final service in IntegrationRegistry.services.skip(1))
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(service.name),
              subtitle: Text('${service.description}\n${service.availability}'),
              isThreeLine: false,
              onTap: () => showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(service.name),
                  content: Text(
                    '${service.description}\n\n${service.availability}\n\nGPX-bestanden kun je via Kaart â†’ GPX importeren openen. Er wordt niet ingelogd of privÃ©data uitgelezen.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => launchUrl(
                        Uri.parse(service.url),
                        mode: LaunchMode.externalApplication,
                      ),
                      child: const Text('OfficiÃ«le informatie'),
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
  String status = 'Status controlerenâ€¦', last = 'nog geen';
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
              ? 'Synchroniserenâ€¦'
              : pending != null
              ? 'Verbindenâ€¦'
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
        'OfficiÃ«le OAuth Â· activiteiten, routes en optionele uploads\n$status\nLaatste synchronisatie: $last',
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
  final backend = TextEditingController(), client = TextEditingController();
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
      if (service is BackendStravaService) await (service as BackendStravaService).refreshStatus();
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
        backend.text =
            await service.store.read('strava-base') ??
            const String.fromEnvironment('STRAVA_BACKEND_URL');
        client.text =
            await service.store.read('strava-client-id') ??
            const String.fromEnvironment('STRAVA_CLIENT_ID', defaultValue: '');
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
          'Handmatig gekozen of expliciet automatisch geselecteerde ritten worden als GPX inclusief GPS-spoor en tijdstippen naar Strava verstuurd. Dit vereist activity:write.',
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
      throw const IntegrationFailure('Kies minstens Ã©Ã©n gegevenscategorie.');
    }
    await service.store.write('strava-client-id', client.text.trim());
    await service.store.write('strava-private', privateData.toString());
    await service.authorize(
      backend.text.trim(),
      client.text.trim(),
      scopes: requested,
    );
    message = 'Rond de officiÃ«le Strava-aanmelding af. Tik op de terugkeerknop op je backendpagina. Deel geen codes of tokens.';
  });
  String get status => coordinator.engine.busy
      ? 'Synchroniserenâ€¦'
      : busy
      ? 'Bezigâ€¦'
      : connecting
      ? 'Verbindenâ€¦'
      : account == null
      ? 'Niet verbonden'
      : state['status'] ?? 'Verbonden';
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Strava Â· account'),
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
                          '${account!['athlete']['firstname'] ?? ''} ${account!['athlete']['lastname'] ?? ''} Â· account ${account!['athlete']['id']}',
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
              if (account == null && service is BackendStravaService)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Meld je eerst aan bij VELO. De beheerder configureert Strava op de server; client secrets blijven daar.',
                  ),
                ),
              if (account == null && service is! BackendStravaService) ...[
                Text(
                  'Zonder server: GPX-uitwisseling',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Text(
                  'Client-ID 292844 en callbackdomein localhost zijn onvoldoende voor veilige zelfstandige OAuth: Strava vereist ook een client secret bij de tokenuitwisseling. De app bewaart geen client secrets. Zonder server zijn automatische accountkoppeling en synchronisatie daarom niet beschikbaar. GPX-uitwisseling werkt wel. Onderstaande backendconfiguratie is uitsluitend optioneel voor een latere keuze.',
                ),
                FilledButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const GpxExchangeScreen(),
                    ),
                  ),
                  child: const Text('GPX uitwisselen zonder server'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: backend,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'OAuth-backend Â· https://â€¦',
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: client,
                  decoration: const InputDecoration(
                    labelText: 'Publiek Strava client-ID',
                  ),
                  keyboardType: TextInputType.number,
                ),
              ],
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
                  'Recente zeven dagen, maximaal 200 activiteiten per poging; alleen je eigen account.',
                ),
                (
                  'routes',
                  'Routes ophalen',
                  'Maximaal tien routes; tijdelijk lokaal voor kaartgebruik.',
                ),
                (
                  'uploads',
                  'Ritten naar Strava versturen',
                  'Alleen geselecteerde eigen ritten; geen geÃ¯mporteerde activiteiten.',
                ),
                (
                  'automatic',
                  'Automatisch synchroniseren',
                  'Android plant achtergrondwerk ongeveer iedere zes uur. Timing is niet gegarandeerd.',
                ),
                (
                  'onOpen',
                  'Bij openen van de app',
                  'Alleen wanneer automatisch synchroniseren aanstaat.',
                ),
                (
                  'afterRide',
                  'Na een opgeslagen rit',
                  'Voegt de nieuwe eigen rit toe als uploaden Ã©n automatisch aanstaan.',
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
                title: const Text('Ook privÃ©activiteiten / privÃ©routes'),
                subtitle: const Text(
                  'Vraagt bij opnieuw verbinden aanvullende read_all-rechten.',
                ),
                value: privateData,
                onChanged: busy ? null : (v) => setState(() => privateData = v),
              ),
              if (account == null &&
                  (service is BackendStravaService ||
                      backend.text.trim().startsWith('https://')))
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
                        : 'Opnieuw verbinden / rechten wijzigen',
                  ),
                ),
              if (account == null &&
                  service is! BackendStravaService &&
                  !backend.text.trim().startsWith('https://'))
                const ListTile(
                  leading: Icon(Icons.lock_outline),
                  title: Text('Accountkoppeling niet geconfigureerd'),
                  subtitle: Text(
                    'Geen server ingesteld. Er wordt geen OAuth-aanmelding of automatische synchronisatie gestart.',
                  ),
                ),
              if (connecting)
                TextButton(
                  onPressed: () => _run(service.cancelAuthorization),
                  child: const Text('Aanmelding annuleren'),
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
                            'GeÃ¯mporteerde gegevens verwijderen?',
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
                            'Trekt toegang online in waar mogelijk en verwijdert lokale tokens, Strava-cache en wachtrij. Je eigen opgenomen ritten blijven behouden.',
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
                            '${ride.totalDistance.toStringAsFixed(1)} km Â· lokaal opgenomen',
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
                      subtitle: Text('${j['status']} Â· ${j['error'] ?? ''}'),
                      trailing: j['status'] == 'failed'
                          ? TextButton(
                              onPressed: () => _run(() async {
                                if (!await _confirm(
                                  'Deze upload opnieuw proberen?',
                                  'Controleer eerst bij Strava of de rit al bestaat. Onzekere uploads worden niet automatisch herhaald.',
                                )) {
                                  return;
                                }
                                await Runtime.database.putDocument(
                                  'sync',
                                  row.key,
                                  jsonEncode({
                                    ...j,
                                    'status': 'pending',
                                    'next': 0,
                                  }),
                                );
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
                    '${row['date']} Â· ${row['trigger']} Â· ${row['status']}',
                  ),
                ),
            ],
          ),
  );
  @override
  void dispose() {
    refresh?.cancel();
    coordinator.engine.removeListener(_changed);
    backend.dispose();
    client.dispose();
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
                    '${a['distance'] / 1000} km Â· ${a['moving_time']} s in beweging\nStrava Â· gesynchroniseerd ${row['synced']}',
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
              'Strava Â· tijdelijk lokaal Â· ook in Kaart â†’ Lokale routes',
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
