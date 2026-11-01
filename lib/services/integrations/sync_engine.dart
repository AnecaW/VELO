import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'integration_models.dart';
import 'strava_integration.dart';

class NetworkState {
  final bool available, wifi;
  const NetworkState(this.available, this.wifi);
  static Future<NetworkState> current() async {
    final values = await Connectivity().checkConnectivity();
    return NetworkState(
      values.any((v) => v != ConnectivityResult.none),
      values.contains(ConnectivityResult.wifi),
    );
  }
}

class SyncEngine extends ChangeNotifier {
  final IntegrationProvider provider;
  final SyncRepository repository;
  final Future<NetworkState> Function() network;
  final DateTime Function() now;
  bool busy = false, _disposed = false;
  void changed() {
    if (!_disposed) notifyListeners();
  }

  SyncEngine(
    this.provider,
    this.repository, {
    Future<NetworkState> Function()? network,
    DateTime Function()? now,
  }) : network = network ?? NetworkState.current,
       now = now ?? DateTime.now;
  static bool permitted(SyncPreferences p, String trigger) =>
      p.enabled &&
      (trigger == 'manual' ||
          trigger == 'reset' ||
          (p.automatic &&
              switch (trigger) {
                'open' => p.onOpen,
                'ride' => p.afterRide,
                'network' => p.onNetwork,
                'background' => true,
                _ => false,
              }));
  Future<bool> run({String trigger = 'manual', bool reset = false}) async {
    if (busy) return true;
    final preferences = await repository.preferences(provider.id);
    if (!permitted(preferences, trigger)) return true;
    try {
      if (!await provider.connected()) return true;
    } catch (_) {
      await repository.update(provider.id, {
        'error': 'Server niet bereikbaar. Probeer later opnieuw.',
      });
      changed();
      return false;
    }
    final state = await repository.state(provider.id), time = now();
    final next = DateTime.tryParse(state['next'] ?? '');
    // Manual retries also honor server retry-after and exponential backoff.
    if (next != null && next.isAfter(time)) return false;
    if (trigger != 'manual' && trigger != 'reset') {
      final last = DateTime.tryParse(state['lastSuccess'] ?? '');
      if (last != null && time.difference(last) < const Duration(minutes: 15)) {
        return true;
      }
    }
    final lease =
        '${time.microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 30)}';
    final acquired = await repository.db.transaction(() async {
      final current = await repository.state(provider.id);
      final until = DateTime.tryParse(current['leaseUntil'] ?? '');
      if (until != null && until.isAfter(time)) return false;
      await repository.update(provider.id, {
        'lease': lease,
        'leaseUntil': time.add(const Duration(minutes: 15)).toIso8601String(),
      });
      return true;
    });
    if (!acquired) return true;
    busy = true;
    if (!_disposed) notifyListeners();
    try {
      final status = await network();
      if (!status.available || (preferences.wifiOnly && !status.wifi)) {
        throw IntegrationFailure(
          preferences.wifiOnly
              ? 'Wacht op wifi; er zijn geen gegevens verstuurd.'
              : 'Offline; synchronisatie staat in de wachtrij.',
          retryAfter: const Duration(minutes: 1),
        );
      }
      await repository.update(provider.id, {
        'status': 'Synchroniseren…',
        'error': null,
      });
      await provider.synchronize(preferences, reset: reset);
      if (!await provider.connected()) return true;
      await repository.update(provider.id, {
        'status': 'Verbonden',
        'error': null,
        'attempts': 0,
        'next': null,
        'lastSuccess': now().toUtc().toIso8601String(),
      });
      await repository.history(
        provider.id,
        trigger,
        'success',
        'Synchronisatie geslaagd',
      );
      return true;
    } catch (e) {
      if (e is IntegrationPending) {
        await repository.update(provider.id, {
          'status': 'Synchronisatie bezig',
          'error': null,
          'next': now()
              .add(const Duration(seconds: 30))
              .toUtc()
              .toIso8601String(),
        });
        return true;
      }
      final failure = e is IntegrationFailure
          ? e
          : const IntegrationFailure(
              'Synchronisatie niet voltooid. Controleer internet en probeer later opnieuw.',
              retryAfter: Duration(minutes: 5),
            );
      if (failure.authentication && provider is StravaIntegration) {
        final p = provider as StravaIntegration;
        await p.service.store.write('strava-reconnect', 'true');
        await p.cache.expire(all: true);
      }
      final attempts = (state['attempts'] as int? ?? 0) + 1;
      final delay =
          failure.retryAfter ??
          Duration(minutes: min(360, 1 << min(attempts, 8)));
      await repository.update(provider.id, {
        'status': failure.authentication
            ? 'Opnieuw verbinden'
            : 'Synchronisatie mislukt',
        'error': failure.message,
        'attempts': attempts,
        'next': failure.authentication
            ? null
            : now().add(delay).toUtc().toIso8601String(),
      });
      await repository.history(provider.id, trigger, 'error', failure.message);
      return failure.authentication;
    } finally {
      final current = await repository.state(provider.id);
      if (current['lease'] == lease) {
        await repository.update(provider.id, {
          'lease': null,
          'leaseUntil': null,
        });
      }
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
