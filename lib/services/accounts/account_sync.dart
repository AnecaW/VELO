import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../database/bike_computer_database.dart';
import '../ride/ride_history_service.dart';
import '../ride/session_codec.dart';
import 'account_service.dart';

/// Incremental account sync with optimistic writes, deletion tracking and local archives.
/// Provider caches and tokens are deliberately excluded.
class AccountSync extends ChangeNotifier {
  final BikeComputerDatabase database;
  final AccountService accounts;
  final Future<void> Function()? onSettingsChanged;
  AccountSync(this.database, this.accounts, {this.onSettingsChanged});
  static const categories = {
    'ride': 'rides',
    'routes': 'routes',
    'training-plans': 'training_plans',
    'settings': 'settings',
    'profiles': 'profiles',
    'training-profile': 'training_profile',
    'training-results': 'training_results',
    'sensors': 'sensor_configs',
    'favorites': 'favorites',
  };
  static const _deviceSettings = {
    'offlineMap',
    'mapImportPath',
    'vectorStylePath',
    'customStyle',
  };
  String _portable(String category, String id, String raw) {
    if (category == 'favorites') {
      try {
        if (jsonDecode(raw) is Map) return raw;
      } catch (_) {}
      return jsonEncode({'value': raw});
    }
    if (category == 'sensors') {
      try {
        if (jsonDecode(raw) is Map) return raw;
      } catch (_) {}
      return jsonEncode({'name': raw});
    }
    if (category != 'settings' || id != 'app') return raw;
    final values = Map<String, dynamic>.from(jsonDecode(raw));
    values.removeWhere(
      (key, value) =>
          _deviceSettings.contains(key) ||
          RegExp(
            r'(password|secret|token|apikey)',
            caseSensitive: false,
          ).hasMatch(key),
    );
    return jsonEncode(values);
  }

  StreamSubscription<String>? _changes;
  Timer? _periodic, _debounce;
  Future<void>? _running;
  int _epoch = 0;
  bool _applying = false, _disposed = false;
  String? message;
  bool get busy => _running != null;
  DateTime? lastSuccess;

  void initialize() {
    if (_changes != null) return;
    _changes = database.documentChanges.listen((category) {
      if (!_applying && categories.containsKey(category)) schedule();
    });
    accounts.addListener(_accountChanged);
    _periodic = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(_tick()),
    );
    schedule();
  }

  Future<void> _tick() async {
    try {
      await accounts.flushPendingLogouts();
    } catch (_) {
      /* Retry next tick. */
    }
    await run();
  }

  void _accountChanged() {
    if (accounts.state == AccountState.signedIn && _running == null) schedule();
  }

  void schedule() {
    if (accounts.user == null || _disposed || _running != null) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () => unawaited(run()));
  }

  String _key(String owner, String category, String id) =>
      jsonEncode([owner, category, id]);
  String _fingerprint(String raw) {
    dynamic ordered(dynamic value) {
      if (value is Map) {
        final keys = value.keys.map((k) => k.toString()).toList()..sort();
        return {for (final key in keys) key: ordered(value[key])};
      }
      if (value is List) return value.map(ordered).toList();
      return value;
    }

    return sha256
        .convert(utf8.encode(jsonEncode(ordered(jsonDecode(raw)))))
        .toString();
  }

  Future<Map<String, dynamic>> _meta(
    String owner,
    String category,
    String id,
  ) async => Map<String, dynamic>.from(
    jsonDecode(
      await database.getDocument(
            'account-sync-meta',
            _key(owner, category, id),
          ) ??
          '{}',
    ),
  );

  Future<void> _remember(
    String owner,
    String category,
    String id,
    int revision,
    String? raw,
  ) => database.putDocument(
    'account-sync-meta',
    _key(owner, category, id),
    jsonEncode({
      'revision': revision,
      'hash': raw == null ? null : _fingerprint(raw),
      'deleted': raw == null,
    }),
  );

  Future<void> _apply(String category, String id, String? raw) async {
    if (category == 'ride') {
      if (raw == null) {
        await database.removeDocument('ride', id);
        await database.deleteRideByRideId(id);
      } else {
        await RideHistoryService(
          database: database,
        ).saveRide(SessionCodec.decode(raw), replace: true, clearActive: false);
      }
    } else if (raw == null) {
      await database.removeDocument(category, id);
    } else {
      if (category == 'settings' && id == 'app') {
        final previous =
            jsonDecode(await database.getDocument(category, id) ?? '{}') as Map;
        raw = jsonEncode({
          ...jsonDecode(raw),
          for (final key in _deviceSettings)
            if (previous.containsKey(key)) key: previous[key],
        });
      }
      await database.putDocument(category, id, raw);
    }
  }

  Future<void> _preserve(
    String owner,
    String category,
    String id,
    String raw,
  ) async {
    final key =
        '${DateTime.now().microsecondsSinceEpoch}-${_fingerprint(raw).substring(0, 12)}';
    await database.putDocument(
      'account-conflict',
      key,
      jsonEncode({
        'owner': owner,
        'category': category,
        'id': id,
        'raw': raw,
        'created': DateTime.now().toUtc().toIso8601String(),
      }),
    );
  }

  Future<void> restoreVersion(String key) async {
    final raw = await database.getDocument('account-conflict', key);
    if (raw == null) return;
    final saved = jsonDecode(raw);
    if (saved['owner'] != accounts.user?['id']) {
      throw AccountFailure('Deze versie hoort bij een ander account.');
    }
    await _apply(saved['category'], saved['id'], saved['raw']);
    if (saved['category'] == 'settings') await onSettingsChanged?.call();
    await database.removeDocument('account-conflict', key);
    schedule();
  }

  /// Archive before sign-out, then restore only the selected account's data.
  /// Unclaimed rides from guest mode are adopted on the next explicit sign-in.
  Future<void> switchIdentity(String? next) async {
    _epoch++;
    _debounce?.cancel();
    final previous = await database.getDocument('account-owner', 'current');
    if (previous == next) return;
    // Cancel through the epoch instead of awaiting a sync which may itself be
    // restoring an expired session and calling this method.
    _applying = true;
    try {
      await database.transaction(() async {
        if (previous != null) {
          final snapshot = <String, Map<String, String>>{};
          for (final category in categories.keys) {
            snapshot[category] = await database.documents(category);
          }
          await database.putDocument(
            'account-archive',
            previous,
            jsonEncode(snapshot),
          );
          for (final entry in snapshot.entries) {
            for (final id in entry.value.keys) {
              await database.removeDocument(entry.key, id);
            }
          }
          await database.deleteRideHistory();
          await database.removeDocument('navigation', 'selected');
          await database.removeDocument('navigation', 'source');
        }
        if (next != null) {
          final archived = await database.getDocument('account-archive', next);
          if (archived != null) {
            final snapshot = jsonDecode(archived) as Map;
            for (final category in categories.keys) {
              for (final entry in (snapshot[category] as Map? ?? {}).entries) {
                final existing = await database.getDocument(
                  category,
                  entry.key,
                );
                if (existing != null && existing != entry.value) {
                  await _preserve(next, category, entry.key, existing);
                }
                await _apply(category, entry.key, entry.value);
              }
            }
          }
          await database.putDocument('account-owner', 'current', next);
        } else {
          await database.removeDocument('account-owner', 'current');
        }
        await database.putDocument(
          'account-owner',
          'generation',
          '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}',
        );
      });
      await onSettingsChanged?.call();
    } finally {
      _applying = false;
    }
  }

  /// Upgrade only the previous, still locally authenticated account. The caller
  /// checks its securely stored identity against the new authenticated email.
  /// Other archived accounts are never claimed by a fresh registration.
  Future<void> importLegacyArchive(String previous, String owner) async {
    final marker = jsonEncode([previous, owner]);
    if (await database.getDocument('account-migrations', marker) != null) {
      return;
    }
    final raw = await database.getDocument('account-archive', previous);
    if (raw == null) return;
    await database.transaction(() async {
      if (await database.getDocument('account-owner', 'current') != owner) {
        return;
      }
      final snapshot = jsonDecode(raw) as Map;
      for (final category in categories.keys) {
        for (final item in (snapshot[category] as Map? ?? {}).entries) {
          final existing = await database.getDocument(category, item.key);
          if (existing != null && existing != item.value) {
            await _preserve(owner, category, item.key, existing);
          }
          await _apply(category, item.key, item.value);
        }
      }
      await database.putDocument('account-migrations', marker, 'complete');
    });
    await onSettingsChanged?.call();
  }

  Future<void> forgetUser(String owner) async {
    await switchIdentity(null);
    await database.removeDocument('account-archive', owner);
    for (final entry in (await database.documents(
      'strava-upload-outbox',
    )).entries) {
      if (jsonDecode(entry.value)['owner'] == owner) {
        await database.removeDocument('strava-upload-outbox', entry.key);
      }
    }
    for (final category in ['account-sync-meta', 'account-sync-cursor']) {
      for (final key in (await database.documents(category)).keys) {
        if ((jsonDecode(key) as List).first == owner) {
          await database.removeDocument(category, key);
        }
      }
    }
    for (final entry in (await database.documents(
      'account-conflict',
    )).entries) {
      if (jsonDecode(entry.value)['owner'] == owner) {
        await database.removeDocument('account-conflict', entry.key);
      }
    }
  }

  Future<void> run() => _running ??= _sync().whenComplete(() {
    _running = null;
    if (!_disposed) notifyListeners();
  });

  Future<void> _sync() async {
    final owner = accounts.user?['id'] as String?;
    if (owner == null || _disposed) return;
    final epoch = _epoch;
    final ownerGeneration = await database.getDocument(
      'account-owner',
      'generation',
    );
    Future<bool> current() async =>
        !_disposed &&
        epoch == _epoch &&
        accounts.user?['id'] == owner &&
        (await database.getDocument('account-owner', 'current')) == owner &&
        (await database.getDocument('account-owner', 'generation')) ==
            ownerGeneration;
    if (await database.getDocument('account-owner', 'current') != owner) return;
    _applying = true;
    try {
      for (final entry in categories.entries) {
        final category = entry.key, kind = entry.value;
        final cursorKey = jsonEncode([owner, category]);
        var cursor =
            int.tryParse(
              await database.getDocument('account-sync-cursor', cursorKey) ??
                  '',
            ) ??
            0;
        try {
          bool more;
          do {
            final page = await accounts.request(
              'GET',
              '/api/v1/data/$kind?after=$cursor&include_deleted=true',
            );
            if (!await current()) return;
            for (final change in page['items'] as List) {
              final applied = await database.transaction(() async {
                if (!await current()) return false;
                final id = change['id'] as String;
                final stored = await database.getDocument(category, id);
                final local = stored == null
                    ? null
                    : _portable(category, id, stored);
                final meta = await _meta(owner, category, id);
                final incoming = change['deleted'] == true
                    ? null
                    : jsonEncode(
                        category == 'profiles'
                            ? change['payload']['value']
                            : change['payload'],
                      );
                final dirty =
                    local != null &&
                    (meta['hash'] == null ||
                        _fingerprint(local) != meta['hash']);
                // The server may echo our last upload after an empty initial pull.
                // This is still the common base, not a concurrent remote change.
                if (meta['revision'] == change['revision'] && dirty) {
                  return true;
                }
                if (dirty &&
                    (incoming == null ||
                        _fingerprint(local) != _fingerprint(incoming))) {
                  await _preserve(owner, category, id, local);
                }
                // A local deletion remains pending when the server version has not changed.
                if (local == null &&
                    meta['deleted'] == false &&
                    meta['revision'] == change['revision']) {
                  return true;
                }
                await _apply(category, id, incoming);
                await _remember(
                  owner,
                  category,
                  id,
                  change['revision'],
                  incoming,
                );
                return true;
              });
              if (!applied) return;
              if (category == 'settings') await onSettingsChanged?.call();
            }
            cursor = page['cursor'] as int;
            more = page['has_more'] == true;
            await database.putDocument(
              'account-sync-cursor',
              cursorKey,
              '$cursor',
            );
          } while (more && await current());
          final local = await database.transaction(() async {
            if (!await current()) return null;
            return database.documents(category);
          });
          if (local == null) return;
          for (final item in local.entries) {
            if (!await current()) return;
            final source = await database.getDocument('route-source', item.key);
            if (item.key.startsWith('strava:') ||
                await database.getDocument('activity-source', item.key) !=
                    null ||
                (source != null && jsonDecode(source)['source'] == 'Strava')) {
              continue;
            }
            final meta = await _meta(owner, category, item.key);
            final portable = _portable(category, item.key, item.value);
            final hash = _fingerprint(portable);
            if (hash == meta['hash'] && meta['deleted'] != true) continue;
            final result = await accounts.request(
              'PUT',
              '/api/v1/data/$kind/${Uri.encodeComponent(item.key)}',
              body: {
                'payload': category == 'profiles'
                    ? {'value': jsonDecode(portable)}
                    : jsonDecode(portable),
                if (meta['revision'] != null)
                  'expected_revision': meta['revision'],
              },
            );
            if (!await current()) return;
            await _remember(
              owner,
              category,
              item.key,
              result['revision'],
              portable,
            );
          }
          for (final item in (await database.documents(
            'account-sync-meta',
          )).entries) {
            final parts = jsonDecode(item.key) as List;
            if (parts[0] != owner ||
                parts[1] != category ||
                local.containsKey(parts[2])) {
              continue;
            }
            final meta = jsonDecode(item.value);
            if (meta['deleted'] == true) continue;
            if (!await current()) return;
            final result = await accounts.request(
              'DELETE',
              '/api/v1/data/$kind/${Uri.encodeComponent(parts[2])}?expected_revision=${meta['revision']}',
            );
            if (!await current()) return;
            if (result['revision'] != null) {
              await _remember(
                owner,
                category,
                parts[2],
                result['revision'],
                null,
              );
            }
          }
        } on AccountFailure catch (e) {
          if (e.status == 409) {
            await database.putDocument('account-sync-cursor', cursorKey, '0');
          }
          rethrow;
        }
      }
      lastSuccess = DateTime.now();
      message = null;
    } catch (_) {
      message = 'Je wijzigingen staan veilig op dit toestel en worden later opnieuw gesynchroniseerd.';
    } finally {
      _applying = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _changes?.cancel();
    _periodic?.cancel();
    _debounce?.cancel();
    accounts.removeListener(_accountChanged);
    super.dispose();
  }
}
