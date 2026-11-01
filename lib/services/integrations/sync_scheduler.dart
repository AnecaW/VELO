import '../accounts/account_service.dart';
import '../accounts/account_sync.dart';
import 'backend_strava.dart';

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:app_links/app_links.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:workmanager/workmanager.dart';
import 'package:bike_computer/database/bike_computer_database.dart';

import 'integration_models.dart';
import 'strava_integration.dart';
import 'sync_engine.dart';

@pragma('vm:entry-point')
void integrationBackgroundDispatcher() {
  Workmanager().executeTask((task, input) async {
    final db = BikeComputerDatabase();
    final accounts = AccountService(refreshMutex: db.withAccountRefreshLock);
    await accounts.restore();
    final strava = BackendStravaService(db, accounts);
    final engine = SyncEngine(
      BackendStravaIntegration(strava),
      SyncRepository(db),
    );
    try {
      final accountSync = AccountSync(db, accounts);
      try {
        await accountSync.run();
      } finally {
        accountSync.dispose();
      }
      await (engine.provider as StravaIntegration).cache.expire();
      if (task == 'strava-cleanup') return true;
      return await engine.run(trigger: 'background');
    } finally {
      strava.dispose();
      engine.dispose();
      await db.close();
    }
  });
}

class IntegrationCoordinator with WidgetsBindingObserver {
  final StravaIntegration strava;
  late final engine = SyncEngine(strava, strava.repository);
  StreamSubscription<Uri>? _links;
  StreamSubscription<List<ConnectivityResult>>? _network;
  Timer? _cleanup;
  bool _initialized = false, _callbackBusy = false;
  String? oauthMessage;
  final Future<void> Function()? syncAccount;
  IntegrationCoordinator(this.strava, {this.syncAccount});
  Future<void> initialize() async {
    if (_initialized || !Platform.isAndroid) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    final links = AppLinks();
    _links = links.uriLinkStream.listen((uri) => handleLink(uri));
    final initial = await links.getInitialLink();
    if (initial != null) await handleLink(initial);
    _network = Connectivity().onConnectivityChanged.listen((_) {
      unawaited(syncAccount?.call() ?? Future.value());
      unawaited(engine.run(trigger: 'network'));
    });
    _cleanup = Timer.periodic(
      const Duration(minutes: 1),
      (_) => strava.cache.expire(),
    );
    await strava.cache.expire();
    await Workmanager().initialize(integrationBackgroundDispatcher);
    await schedule();
    unawaited(engine.run(trigger: 'open'));
  }

  Future<void> handleLink(Uri uri) async {
    if (uri.scheme != 'ultimatebike' ||
        uri.host != 'oauth' ||
        uri.path != '/strava' ||
        _callbackBusy) {
      return;
    }
    _callbackBusy = true;
    try {
      await strava.service.handleCallback(uri);
      oauthMessage = 'Strava-account verbonden. Kies welke gegevens je wilt synchroniseren.';
      await strava.repository.update('strava', {
        'status': 'Verbonden',
        'error': null,
        'next': null,
      });
      await schedule();
      unawaited(engine.run(trigger: 'open'));
    } catch (e) {
      oauthMessage = e is IntegrationFailure
          ? e.message
          : 'Verbinden is niet gelukt. Probeer opnieuw.';
      await strava.repository.update('strava', {'error': oauthMessage});
    } finally {
      _callbackBusy = false;
      engine.changed();
    }
  }

  Future<void> schedule() async {
    if (!Platform.isAndroid) return;
    final p = await strava.repository.preferences('strava');
    await Workmanager().cancelByUniqueName('bike-strava-periodic');
    await Workmanager().cancelByUniqueName('bike-strava-pending');
    await Workmanager().registerPeriodicTask(
      'bike-strava-cleanup',
      'strava-cleanup',
      frequency: const Duration(hours: 6),
    );
    if (!p.enabled || !p.automatic || !await strava.connected()) return;
    final constraints = Constraints(
      networkType: p.wifiOnly ? NetworkType.unmetered : NetworkType.connected,
      requiresBatteryNotLow: true,
    );
    await Workmanager().registerPeriodicTask(
      'bike-strava-periodic',
      'strava-sync',
      frequency: const Duration(hours: 6),
      constraints: constraints,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 5),
    );
    await Workmanager().registerOneOffTask(
      'bike-strava-pending',
      'strava-sync',
      constraints: constraints,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 5),
    );
  }

  Future<void> rideSaved(String id) async {
    final p = await strava.repository.preferences('strava');
    if (!SyncEngine.permitted(p, 'ride') ||
        !p.uploads ||
        !await strava.connected()) {
      return;
    }
    await strava.service.enqueue(id);
    await schedule();
    unawaited(engine.run(trigger: 'ride'));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(syncAccount?.call() ?? Future.value());
      strava.cache.expire();
      engine.run(trigger: 'open');
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _links?.cancel();
    _network?.cancel();
    _cleanup?.cancel();
    engine.dispose();
    strava.service.dispose();
  }
}
