import '../../services/integrations/strava_integration.dart';
import '../../widgets/velo_ui.dart';
import 'strava_upload_card.dart';
import '../../services/integrations/strava_activity.dart';

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
    timer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  void _changed() {
    _load();
  }

  Future<void> _load() async {
    try {
      final c = Runtime.integrations,
          a = await c.strava.service.account(),
          s = await c.strava.repository.state('strava');
      final awaitInfo = c.strava.service is BackendStravaService
          ? await (c.strava.service as BackendStravaService).information()
          : null;
      final pending = await c.strava.service.store.read('strava-state');
      if (mounted) {
        setState(() {
          status = c.engine.busy
              ? 'Synchroniseren…'
              : pending != null
              ? 'Verbinden…'
              : c.strava.service is BackendStravaService &&
                    (awaitInfo?['configured'] == false)
              ? 'Configuratie ontbreekt'
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
  SyncPreferences preferences = const SyncPreferences();
  Map<String, dynamic> info = {}, state = {};
  List<Map<String, dynamic>> history = [];
  Map<String, String> jobs = {};
  bool loading = true,
      busy = false,
      reading = false,
      connecting = false,
      privateData = false;
  int historyDays = 30;
  String? message;
  Timer? refresh;
  String? identity;
  void _accountChanged() {
    final next = backend?.accounts.user?['id'] as String?;
    if (next == identity) return;
    identity = next;
    if (mounted) {
      setState(() {
        info = {};
        state = {};
        jobs = {};
        history = [];
        loading = true;
        message = null;
      });
    }
    _load();
  }

  BackendStravaService? get backend =>
      service is BackendStravaService ? service as BackendStravaService : null;
  bool get connected => info['connected'] == true;
  String get status => backend != null && backend!.accounts.user == null
      ? 'Verbinden vereist'
      : loading
      ? 'Status controleren…'
      : info['configured'] == false
      ? 'Configuratie ontbreekt'
      : connecting
      ? 'Verbinding maken…'
      : info['status'] == 'needs_reconnect'
      ? 'Verbinden vereist'
      : coordinator.engine.busy ||
            ['pending', 'running'].contains(info['sync_status'])
      ? 'Synchronisatie bezig'
      : info['sync_status'] == 'failed'
      ? 'Synchronisatie mislukt'
      : connected
      ? state['status'] ?? 'Verbonden'
      : 'Niet verbonden';
  @override
  void initState() {
    super.initState();
    identity = backend?.accounts.user?['id'] as String?;
    backend?.accounts.addListener(_accountChanged);
    _load();
    coordinator.engine.addListener(_changed);
    refresh = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  void _changed() {
    _load();
  }

  Future<void> _load() async {
    if (reading) return;
    reading = true;
    final readingOwner = backend?.accounts.user?['id'];
    try {
      if (backend != null) {
        await backend!.refreshStatus();
        info = await backend!.information();
      } else {
        final a = await service.account();
        info = {'configured': true, 'connected': a != null, ...?a};
      }
      final p = await repo.preferences('strava'),
          st = await repo.state('strava');
      final started = DateTime.tryParse(
        await service.store.read('strava-auth-started') ?? '',
      );
      var pending = await service.store.read('strava-state') != null;
      if (pending &&
          (started == null ||
              DateTime.now().difference(started) >
                  const Duration(minutes: 10))) {
        await service.cancelAuthorization();
        pending = false;
      }
      if (connected && provider is BackendStravaIntegration) {
        await (provider as BackendStravaIntegration).loadCached();
      }
      final h =
          (await service.database.documents('sync-history')).values
              .map((v) => jsonDecode(v) as Map<String, dynamic>)
              .where((v) => v['provider'] == 'strava')
              .toList()
            ..sort((a, b) => b['date'].compareTo(a['date']));
      final j = await service.database.documents('sync');
      if (backend != null && backend!.accounts.user?['id'] != readingOwner) {
        return;
      }
      if (mounted) {
        setState(() {
          preferences = p;
          state = st;
          history = h;
          jobs = j;
          connecting = pending;
          loading = false;
          historyDays =
              (info['preferences']?['history_days'] as num?)?.toInt() ?? 30;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          message = e is AccountFailure ? e.message : 'De verbindingsstatus kon niet worden opgehaald. Controleer internet en probeer opnieuw.';
        });
      }
    } finally {
      reading = false;
      if (mounted &&
          backend != null &&
          backend!.accounts.user?['id'] != readingOwner) {
        _load();
      }
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(
          () => message = e is AccountFailure
              ? e.message
              : e is IntegrationFailure
              ? e.message
              : 'De actie kon niet worden voltooid. Probeer opnieuw.',
        );
      }
    } finally {
      backend?.invalidateStatus();
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
  Future<void> _save() async {
    await repo.savePreferences('strava', preferences);
    if (backend != null && connected) {
      await backend!.accounts.request(
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
          'history_days': historyDays,
        },
      );
    }
    await coordinator.schedule();
  }

  Future<void> _change(String key, bool value) => _run(() async {
    preferences = preferences.withValue(key, value);
    await _save();
  });
  Future<void> _autoUpload(bool value) => _run(() async {
    if (value &&
        !await _confirm(
          'Ritten automatisch delen?',
          'Nieuwe eigen ritten worden na het opslaan met hun echte GPS-spoor en tijdstempels naar Strava verstuurd. Bestaande ritten worden niet automatisch toegevoegd.',
        )) {
      return;
    }
    preferences = preferences
        .withValue('uploads', value)
        .withValue('afterRide', value);
    if (value) {
      preferences = preferences
          .withValue('enabled', true)
          .withValue('automatic', true);
    }
    await _save();
  });
  Future<void> _connect() => _run(() async {
    preferences = preferences.withValue('enabled', true);
    await repo.savePreferences('strava', preferences);
    await service.store.write('strava-private', privateData.toString());
    await service.authorize(
      '',
      '',
      scopes: [
        'read',
        privateData ? 'activity:read_all' : 'activity:read',
        'activity:write',
      ],
    );
    message = 'Geef toestemming bij Strava. Daarna keer je automatisch terug naar VELO.';
  });
  String _formatSync(String? value) {
    final date = DateTime.tryParse(value ?? '')?.toLocal();
    if (date == null) return 'nog geen';
    String n(int value) => value.toString().padLeft(2, '0');
    return '${n(date.day)}/${n(date.month)}/${date.year} ${n(date.hour)}:${n(date.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final athlete = info['athlete'] as Map?;
    final photo = athlete?['profile_medium'] ?? athlete?['profile'];
    final hasPhoto = photo is String && Uri.tryParse(photo)?.scheme == 'https';
    final name = athlete == null
        ? 'Strava'
        : ('${athlete['firstname'] ?? ''} ${athlete['lastname'] ?? ''}').trim();
    final rights = info['features'] as Map? ?? {};
    return Scaffold(
      appBar: AppBar(
        title: const Text('Strava'),
        actions: [
          IconButton(
            tooltip: 'Status vernieuwen',
            onPressed: busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: VeloPageList(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundImage: hasPhoto ? NetworkImage(photo) : null,
                    child: hasPhoto ? null : const Icon(Icons.directions_bike),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name.isEmpty ? 'Strava' : name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(status, key: const ValueKey('strava-status')),
                        if (athlete?['username'] != null)
                          Text('@${athlete!['username']}'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (loading || busy || coordinator.engine.busy)
            const LinearProgressIndicator(),
          if (message ?? coordinator.oauthMessage ?? state['error']
              case final String m)
            VeloNotice(m),
          if (loading)
            const SizedBox(height: 8)
          else if (backend != null && backend!.accounts.user == null) ...[
            const Text(
              'Meld je aan bij VELO om je eigen Strava-account veilig te koppelen.',
            ),
            FilledButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const AccountScreen()),
              ),
              child: const Text('Aanmelden bij VELO'),
            ),
          ] else if (info['configured'] == false) ...[
            const VeloNotice(
              'Configuratie ontbreekt. De beheerder moet de Strava-app activeren. Je lokale ritten blijven beschikbaar.',
            ),
          ] else ...[
            if (!connected)
              const Text(
                'Verbind je eigen Strava-account om activiteiten op te halen en opgenomen ritten te delen. Automatisch uploaden staat standaard uit.',
              ),
            if (!connected || info['status'] == 'needs_reconnect')
              Semantics(
                button: true,
                label: 'Verbinden met Strava',
                child: InkWell(
                  key: const ValueKey('connect-strava'),
                  onTap: busy ? null : _connect,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Image.asset(
                      'assets/images/strava-connect.png',
                      height: 48,
                    ),
                  ),
                ),
              ),
            if (connecting)
              TextButton(
                onPressed: () => _run(service.cancelAuthorization),
                child: const Text('Verbinden annuleren'),
              ),
            if (connected) ...[
              Text(
                'Laatste synchronisatie: ${_formatSync(state['lastSuccess'] as String?)}',
              ),
              Text(
                '${info['counts']?['activities'] ?? 0} activiteiten · ${info['counts']?['routes'] ?? 0} routes',
              ),
              if (rights['activities'] == false || rights['uploads'] == false)
                VeloNotice(
                  'Niet alle rechten zijn toegestaan. ${rights['activities'] == false ? 'Activiteiten ophalen is uitgeschakeld. ' : ''}${rights['uploads'] == false ? 'Uploaden is uitgeschakeld.' : ''} Pas de toestemming aan om die functie te gebruiken.',
                ),
              OutlinedButton(
                onPressed: busy || coordinator.engine.busy
                    ? null
                    : () => _run(() async {
                        await coordinator.engine.run();
                      }),
                child: const Text('Synchroniseer nu'),
              ),
              OutlinedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const StravaDataScreen(),
                  ),
                ),
                child: const Text('Activiteiten en routes bekijken'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Nieuwe VELO-ritten automatisch uploaden'),
                subtitle: const Text(
                  'Alleen na het opslaan; je kunt iedere eigen rit ook handmatig delen.',
                ),
                value:
                    preferences.uploads &&
                    preferences.automatic &&
                    preferences.afterRide,
                onChanged: busy || rights['uploads'] == false
                    ? null
                    : _autoUpload,
              ),
              TextButton(
                onPressed: busy ? null : _connect,
                child: const Text('Toestemming aanpassen'),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () => _run(() async {
                        if (await _confirm(
                          'Strava ontkoppelen?',
                          'De toestemming en opgehaalde Strava-gegevens worden verwijderd. Eigen VELO-ritten blijven bewaard.',
                        )) {
                          await provider.disconnect();
                          await coordinator.schedule();
                        }
                      }),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                child: const Text('Strava ontkoppelen'),
              ),
              TextButton(
                onPressed: () => launchUrl(
                  Uri.parse('https://www.strava.com/settings/apps'),
                  mode: LaunchMode.externalApplication,
                ),
                child: const Text('Koppeling beheren bij Strava'),
              ),
            ],
            VeloSection(
              title: 'Gegevens en synchronisatie',
              children: [
                SwitchListTile(
                  title: const Text('Activiteiten ophalen'),
                  value: preferences.activities,
                  onChanged: busy ? null : (v) => _change('activities', v),
                ),
                SwitchListTile(
                  title: const Text('Routes ophalen'),
                  value: preferences.routes,
                  onChanged: busy ? null : (v) => _change('routes', v),
                ),
                SwitchListTile(
                  title: const Text('Ook privéactiviteiten'),
                  subtitle: const Text(
                    'Vraagt activity:read_all aan. Geef hiervoor opnieuw toestemming bij Strava.',
                  ),
                  value: privateData,
                  onChanged: busy
                      ? null
                      : (v) => setState(() => privateData = v),
                ),
                ListTile(
                  title: const Text('Recente activiteiten'),
                  trailing: DropdownButton<int>(
                    value: [7, 30, 90, 365].contains(historyDays)
                        ? historyDays
                        : 30,
                    items: [
                      for (final d in [7, 30, 90, 365])
                        DropdownMenuItem(value: d, child: Text('$d dagen')),
                    ],
                    onChanged:
                        busy ||
                            !connected ||
                            coordinator.engine.busy ||
                            ['pending', 'running'].contains(info['sync_status'])
                        ? null
                        : (v) => _run(() async {
                            historyDays = v!;
                            await _save();
                            await coordinator.engine.run(
                              trigger: 'reset',
                              reset: true,
                            );
                          }),
                  ),
                ),
                SwitchListTile(
                  title: const Text('Gegevensuitwisseling toestaan'),
                  value: preferences.enabled,
                  onChanged: busy ? null : (v) => _change('enabled', v),
                ),
                SwitchListTile(
                  title: const Text('Op de achtergrond bijwerken'),
                  subtitle: const Text(
                    'Activiteitwijzigingen komen via webhooks binnen; periodiek herstel is begrensd.',
                  ),
                  value: preferences.automatic,
                  onChanged: busy ? null : (v) => _change('automatic', v),
                ),
                SwitchListTile(
                  title: const Text('Alleen via wifi op dit toestel'),
                  subtitle: const Text(
                    'Geldt voor verzending door VELO. De cloud kan ontvangen Strava-events blijven verwerken.',
                  ),
                  value: preferences.wifiOnly,
                  onChanged: busy ? null : (v) => _change('wifiOnly', v),
                ),
                SwitchListTile(
                  title: const Text('Bij openen bijwerken'),
                  value: preferences.onOpen,
                  onChanged: busy ? null : (v) => _change('onOpen', v),
                ),
                SwitchListTile(
                  title: const Text('Bij netwerkherstel hervatten'),
                  value: preferences.onNetwork,
                  onChanged: busy ? null : (v) => _change('onNetwork', v),
                ),
              ],
            ),
            if (connected) ...[
              Text(
                'Eigen ritten',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              FutureBuilder(
                future: service.database.getAllRides(),
                builder: (context, snapshot) => Column(
                  children: [
                    if ((snapshot.data ?? []).isEmpty)
                      const Text('Nog geen eigen opgeslagen ritten.'),
                    for (final ride in snapshot.data ?? [])
                      StravaUploadCard(
                        key: ValueKey('strava-upload-${ride.rideId}'),
                        rideId: ride.rideId,
                        service: backend,
                        loadRemote: false,
                      ),
                  ],
                ),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () => _run(() async {
                        await provider.cache.expire(all: true);
                        await coordinator.engine.run(
                          trigger: 'reset',
                          reset: true,
                        );
                      }),
                child: const Text('Recente gegevens opnieuw ophalen'),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () => _run(() async {
                        await provider.cache.expire(all: true);
                      }),
                child: const Text('Lokale Strava-cache verwijderen'),
              ),
            ],
            if (history.isNotEmpty)
              VeloSection(
                title: 'Synchronisatiegeschiedenis',
                children: [
                  for (final row in history.take(10))
                    ListTile(
                      title: Text(row['message']),
                      subtitle: Text('${row['date']} · ${row['status']}'),
                    ),
                ],
              ),
            const Text(
              'Gegevens van Strava worden alleen aan jou getoond en apart van je lokale ritstatistieken bewaard. De cache verloopt binnen 24 uur. Je Strava-tokens blijven versleuteld op de server.',
            ),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    backend?.accounts.removeListener(_accountChanged);
    refresh?.cancel();
    coordinator.engine.removeListener(_changed);
    super.dispose();
  }
}

class StravaDataScreen extends StatefulWidget {
  final StravaIntegration? integration;
  const StravaDataScreen({super.key, this.integration});
  @override
  State<StravaDataScreen> createState() => _StravaDataScreenState();
}

class _StravaDataScreenState extends State<StravaDataScreen> {
  late final provider = widget.integration ?? Runtime.integrations.strava;
  List<Map<String, dynamic>> activities = [];
  Map<String, String> routes = {};
  String? error;
  bool busy = false;
  Timer? timer;
  String? dataOwner;
  AccountService? get ownerAccount => provider.service is BackendStravaService
      ? (provider.service as BackendStravaService).accounts
      : null;
  void _ownerChanged() {
    final next = ownerAccount?.user?['id'] as String?;
    if (next == dataOwner) return;
    dataOwner = next;
    if (mounted) {
      setState(() {
        activities = [];
        routes = {};
        error = null;
      });
    }
    _load();
  }

  @override
  void initState() {
    super.initState();
    dataOwner = ownerAccount?.user?['id'] as String?;
    ownerAccount?.addListener(_ownerChanged);
    _load();
    timer = Timer.periodic(const Duration(minutes: 1), (_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    final readingOwner = ownerAccount?.user?['id'];
    if (ownerAccount != null &&
        (readingOwner == null ||
            await provider.service.database.getDocument(
                  'account-owner',
                  'current',
                ) !=
                readingOwner)) {
      if (mounted) {
        setState(() {
          activities = [];
          routes = {};
        });
      }
      return;
    }
    try {
      await provider.cache.expire();
      if (provider is BackendStravaIntegration) {
        await (provider as BackendStravaIntegration).loadCached();
      }
      final a =
          (await provider.service.database.documents('strava-activities'))
              .values
              .map((v) => jsonDecode(v) as Map<String, dynamic>)
              .toList()
            ..sort(
              (a, b) => (b['data']['start_date'] as String).compareTo(
                a['data']['start_date'] as String,
              ),
            );
      final r = await provider.service.database.documents('routes');
      if (ownerAccount != null && ownerAccount!.user?['id'] != readingOwner) {
        return;
      }
      if (mounted) {
        setState(() {
          activities = a;
          routes = Map.fromEntries(
            r.entries.where((e) => e.key.startsWith('strava:')),
          );
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is AccountFailure
              ? e.message
              : 'Je Strava-gegevens konden niet worden bijgewerkt.',
        );
      }
    }
  }

  Widget _detail(Map<String, dynamic> d) {
    final polyline = d['map']?['polyline'] ?? d['map']?['summary_polyline'];
    var points = <NavPoint>[];
    if (polyline is String) {
      try {
        points = stravaPolyline(polyline);
      } on FormatException {
        /* Display statistics if the provider map is malformed. */
      }
    }
    String speed(dynamic value) => value is num
        ? '${(value * 3.6).toStringAsFixed(1)} km/h'
        : 'niet beschikbaar';
    return SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bron: Strava · ${d['sport_type'] ?? d['type'] ?? 'Activiteit'}',
            ),
            Text(
              'Start: ${DateTime.tryParse(d['start_date'] ?? '')?.toLocal() ?? 'onbekend'}',
            ),
            Text(
              'Afstand: ${((d['distance'] as num? ?? 0) / 1000).toStringAsFixed(2)} km',
            ),
            Text('Bewegingstijd: ${stravaDuration(d['moving_time'])}'),
            Text('Verstreken tijd: ${stravaDuration(d['elapsed_time'])}'),
            Text('Gemiddelde snelheid: ${speed(d['average_speed'])}'),
            Text('Maximumsnelheid: ${speed(d['max_speed'])}'),
            Text(
              'Hoogtemeters: ${d['total_elevation_gain'] ?? 'niet beschikbaar'} m',
            ),
            if (points.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: SizedBox(
                  height: 220,
                  child: RouteMap(
                    route: NavRoute(d['name'] ?? 'Strava-activiteit', points),
                    online: Runtime.settings.value('onlineMap', false),
                  ),
                ),
              ),
            if (points.length < 2)
              const Text('Geen kaartspoor beschikbaar voor deze activiteit.'),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Afkomstig van Strava')),
    body: VeloPageList(
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
                    '${((a['distance'] as num? ?? 0) / 1000).toStringAsFixed(2)} km · ${stravaDuration(a['moving_time'])}\n${a['sport_type'] ?? a['type'] ?? 'Activiteit'} · ${DateTime.tryParse(a['start_date'] ?? '')?.toLocal() ?? ''}\nBron: Strava',
                  ),
                  onTap: busy
                      ? null
                      : () async {
                          setState(() => busy = true);
                          try {
                            final d = await provider.details(a['id']);
                            if (!mounted) return;
                            setState(() => busy = false);
                            await showDialog<void>(
                              context: this.context,
                              builder: (ctx) => AlertDialog(
                                title: Text(d['name'] ?? 'Strava-activiteit'),
                                content: _detail(d),
                                actions: [
                                  TextButton(
                                    onPressed: () => launchUrl(
                                      Uri.parse(
                                        'https://www.strava.com/activities/${a['id']}',
                                      ),
                                      mode: LaunchMode.externalApplication,
                                    ),
                                    style: TextButton.styleFrom(
                                      foregroundColor: const Color(0xfffc5200),
                                    ),
                                    child: const Text(
                                      'View on Strava',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text('Sluiten'),
                                  ),
                                ],
                              ),
                            );
                          } catch (e) {
                            if (mounted) {
                              setState(
                                () => error = e is AccountFailure ? e.message : 'De activiteit kon niet worden geopend. Probeer opnieuw.',
                              );
                            }
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
    ownerAccount?.removeListener(_ownerChanged);
    timer?.cancel();
    super.dispose();
  }
}
