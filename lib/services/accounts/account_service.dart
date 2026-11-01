import 'dart:async';
import 'dart:convert';
import 'dart:io' show InternetAddress;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../integrations/strava_service.dart';

enum AccountState {
  signedOut,
  signingIn,
  signedIn,
  unavailable,
  expired,
  authenticationError,
}

class AccountFailure implements Exception {
  final String message;
  final int? status;
  final String? code;
  AccountFailure(this.message, {this.status, this.code});
  @override
  String toString() => message;
}

class AccountService extends ChangeNotifier {
  final TokenStore store;
  final http.Client client;
  final Future<void> Function(String? userId)? onIdentityChange;
  final Future<void> Function(Future<void> Function())? refreshMutex;
  AccountService({
    TokenStore? store,
    http.Client? client,
    String? baseUrl,
    this.onIdentityChange,
    this.refreshMutex,
  }) : store = store ?? SecureTokenStore(),
       client = client ?? http.Client(),
       base = (baseUrl ?? const String.fromEnvironment('VELO_BACKEND_URL'))
           .replaceAll(RegExp(r'/+$'), '');
  final String base;
  static const _lanBuild = bool.fromEnvironment('VELO_LAN_MODE');
  bool get localNetworkOnly => _lanBuild;
  bool get passwordRecovery => false;
  static bool _privateAddress(String host) {
    final address = InternetAddress.tryParse(host);
    if (address == null || address.rawAddress.length != 4) return false;
    final bytes = address.rawAddress;
    return bytes[0] == 10 ||
        (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
        (bytes[0] == 192 && bytes[1] == 168);
  }

  String? confirmationEmail;
  String? authLinkError;
  Future<void> registerAccount(String name, String email, String password) =>
      login(email, password, register: true);
  Future<void> verifyEmailCode(
    String email,
    String code, {
    bool recovery = false,
  }) async {
    throw AccountFailure('E-mailcodes zijn niet beschikbaar.');
  }

  Future<void> resendVerification(String email) async {
    await request(
      'POST',
      '/api/v1/accounts/resend-verification',
      body: {'email': email},
      authenticated: false,
    );
  }

  Future<void> completePasswordRecovery(String password) async {
    await request(
      'POST',
      '/api/v1/accounts/password',
      body: {'new_password': password},
    );
    await deleted();
  }

  void dismissAuthLinkError() {
    authLinkError = null;
    notifyListeners();
  }

  bool initialized = false;
  AccountState state = AccountState.signedOut;
  Map<String, dynamic>? user;
  String? message;
  Map<String, dynamic>? _tokens;
  Future<void>? _refreshing;
  int _authGeneration = 0;
  void _state(AccountState value, [String? text]) {
    state = value;
    message = text;
    notifyListeners();
  }

  Future<void> restore() async {
    try {
      final origin = await store.read('velo-session-origin');
      // Older configurable builds must never send credentials to another origin.
      final previous = origin ?? await store.read('velo-backend');
      if (previous != null && previous != base) {
        await store.write('velo-session', null);
        return;
      }
      final raw = await store.read('velo-session');
      if (raw == null) return;
      _tokens = jsonDecode(raw) as Map<String, dynamic>;
      if (_tokens!['user'] is Map) {
        user = Map<String, dynamic>.from(_tokens!['user']);
      }
      if (user != null) await onIdentityChange?.call(user?['id'] as String?);
      final restoredUser =
          await request('GET', '/api/v1/me') as Map<String, dynamic>;
      await onIdentityChange?.call(restoredUser['id'] as String?);
      user = restoredUser;
      _tokens!['user'] = restoredUser;
      await store.write('velo-session', jsonEncode(_tokens));
      await store.write('velo-session-origin', base);
      _state(AccountState.signedIn);
    } catch (_) {
      /* request preserves offline credentials */
    } finally {
      initialized = true;
      notifyListeners();
      unawaited(flushPendingLogouts().catchError((Object _) {}));
    }
  }

  Future<dynamic> _send(
    String method,
    String path,
    Object? body,
    String? token,
  ) async {
    if (base.isEmpty) {
      throw AccountFailure(
        'Aanmelden is tijdelijk niet beschikbaar. Je kunt blijven fietsen.',
      );
    }
    final uri = Uri.parse(base);
    if (!uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path != '' && uri.path != '/') ||
        (uri.scheme != 'https' &&
            !(uri.scheme == 'http' &&
                (kDebugMode || (_lanBuild && _privateAddress(uri.host)))))) {
      throw AccountFailure(
        'Er kan geen veilige verbinding met VELO worden gemaakt.',
      );
    }
    final req = http.Request(method, Uri.parse('$base$path'));
    req.headers['Content-Type'] = 'application/json';
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    if (body != null) req.body = jsonEncode(body);
    final response = await http.Response.fromStream(
      await client.send(req).timeout(const Duration(seconds: 20)),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 401) {
      if (data['error']?['code'] == 'invalid_credentials' &&
          path != '/api/v1/accounts/login') {
        throw AccountFailure(data['error']['message']);
      }
      throw _Unauthorized();
    }
    if (response.statusCode >= 400) {
      throw AccountFailure(
        data['error']?['message'] ?? 'Serververzoek mislukt.',
        status: response.statusCode,
        code: data['error']?['code'],
      );
    }
    return data;
  }

  Future<void> _refresh() async {
    if (refreshMutex != null) return refreshMutex!(_renew);
    return _renew();
  }

  Future<void> _renew() async {
    final stored = await store.read('velo-session');
    if (stored != null) {
      final latest = Map<String, dynamic>.from(jsonDecode(stored));
      if (latest['user']?['id'] != _tokens?['user']?['id']) {
        _tokens = null;
        user = null;
        _state(AccountState.signedOut);
        throw AccountFailure('Je account is gewijzigd. Open VELO opnieuw.');
      }
      if (latest['refresh_token'] != _tokens?['refresh_token'] &&
          (latest['expires_at'] as num) * 1000 >
              DateTime.now().millisecondsSinceEpoch + 30000) {
        _tokens = latest;
        return;
      }
    }
    try {
      final next = await _send('POST', '/api/v1/accounts/refresh', {
        'refresh_token': _tokens?['refresh_token'],
      }, null);
      _tokens = {
        ...Map<String, dynamic>.from(next),
        'user': user ?? _tokens?['user'],
      };
      await store.write('velo-session', jsonEncode(_tokens));
    } on _Unauthorized {
      _authGeneration++;
      await onIdentityChange?.call(null);
      _tokens = null;
      user = null;
      await store.write('velo-session', null);
      _state(AccountState.expired, 'Sessie verlopen. Meld opnieuw aan.');
      throw AccountFailure(message!);
    }
  }

  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    bool authenticated = true,
  }) async {
    final generation = _authGeneration;
    void checkGeneration() {
      if (generation != _authGeneration) {
        throw AccountFailure(
          'Je aanmelding is gewijzigd. Probeer opnieuw.',
          code: 'session_changed',
        );
      }
    }

    try {
      if (authenticated && _tokens == null) {
        throw AccountFailure('Meld je eerst aan bij VELO.');
      }
      if (authenticated &&
          (_tokens!['expires_at'] as num) * 1000 <=
              DateTime.now().millisecondsSinceEpoch + 30000) {
        await (_refreshing ??= _refresh().whenComplete(
          () => _refreshing = null,
        ));
        checkGeneration();
      }
      try {
        final value = await _send(
          method,
          path,
          body,
          authenticated ? (_tokens!['access_token'] as String) : null,
        );
        checkGeneration();
        if (authenticated) _state(AccountState.signedIn);
        return value;
      } on _Unauthorized {
        checkGeneration();
        if (!authenticated) {
          _state(
            AccountState.authenticationError,
            'E-mailadres of wachtwoord is onjuist.',
          );
          throw AccountFailure(message!);
        }
        await (_refreshing ??= _refresh().whenComplete(
          () => _refreshing = null,
        ));
        checkGeneration();
        try {
          final value = await _send(
            method,
            path,
            body,
            _tokens?['access_token'],
          );
          checkGeneration();
          return value;
        } on _Unauthorized {
          _state(AccountState.expired, 'Sessie verlopen. Meld opnieuw aan.');
          throw AccountFailure(message!);
        }
      }
    } on AccountFailure {
      rethrow;
    } catch (_) {
      checkGeneration();
      _state(
        AccountState.unavailable,
        _lanBuild
            ? 'Geen verbinding met VELO. Controleer of je met je thuisnetwerk bent verbonden. Je fietscomputer blijft werken.'
            : 'VELO is tijdelijk niet bereikbaar. Je fietscomputer blijft werken. Probeer later opnieuw.',
      );
      throw AccountFailure(message!);
    }
  }

  Future<void> login(
    String email,
    String password, {
    bool register = false,
  }) async {
    if (refreshMutex != null) {
      return refreshMutex!(() => _login(email, password, register: register));
    }
    return _login(email, password, register: register);
  }

  Future<void> _login(
    String email,
    String password, {
    bool register = false,
  }) async {
    _authGeneration++;
    user = null;
    _state(AccountState.signingIn);
    try {
      _tokens = Map<String, dynamic>.from(
        await request(
          'POST',
          '/api/v1/accounts/${register ? 'register' : 'login'}',
          body: {'email': email, 'password': password},
          authenticated: false,
        ),
      );
      await onIdentityChange?.call(_tokens!['user']['id'] as String);
      user = Map<String, dynamic>.from(_tokens!['user']);
      await store.write('velo-session', jsonEncode(_tokens));
      await store.write('velo-session-origin', base);
      initialized = true;
      _state(AccountState.signedIn);
      unawaited(flushPendingLogouts().catchError((Object _) {}));
    } on AccountFailure catch (e) {
      if (state == AccountState.signingIn) {
        _state(AccountState.authenticationError, e.message);
      }
      rethrow;
    }
  }

  Future<void> logout() async {
    if (refreshMutex != null) return refreshMutex!(_logout);
    return _logout();
  }

  Future<void> _logout() async {
    _authGeneration++;
    final stored = await store.read('velo-session');
    final latest = stored == null ? null : jsonDecode(stored);
    final refresh = (latest?['user']?['id'] == user?['id'])
        ? (latest?['refresh_token'] ?? _tokens?['refresh_token'])
        : (_tokens?['refresh_token']);
    var deferred = false;
    if (refresh != null) {
      try {
        await request(
          'POST',
          '/api/v1/accounts/logout',
          body: {'refresh_token': refresh},
          authenticated: false,
        );
      } on AccountFailure {
        final pending =
            jsonDecode(await store.read('velo-pending-logout') ?? '[]') as List;
        if (!pending.any((row) => row['token'] == refresh)) {
          pending.add({
            'origin': base,
            'token': refresh,
            'expires': DateTime.now()
                .add(const Duration(days: 30))
                .millisecondsSinceEpoch,
          });
        }
        await store.write('velo-pending-logout', jsonEncode(pending));
        deferred = true;
      }
    }
    await onIdentityChange?.call(null);
    _authGeneration++;
    _tokens = null;
    user = null;
    await store.write('velo-session', null);
    _state(
      AccountState.signedOut,
      deferred
          ? 'Je bent op dit toestel uitgelogd. Zodra er verbinding is, ronden we dit af.'
          : null,
    );
  }

  /// Revocation-only credentials stay in secure storage, never in the local DB.
  /// They are not used for login or sent to a different internally configured origin.
  Future<void> flushPendingLogouts() async {
    if (await store.read('velo-pending-logout') == null) return;
    Future<void> flush() async {
      final pending =
          jsonDecode(await store.read('velo-pending-logout') ?? '[]') as List;
      final remaining = <dynamic>[];
      for (final row in pending) {
        if ((row['expires'] as num) < DateTime.now().millisecondsSinceEpoch) {
          continue;
        }
        if (row['origin'] != base) {
          remaining.add(row);
          continue;
        }
        try {
          await _send('POST', '/api/v1/accounts/logout', {
            'refresh_token': row['token'],
          }, null);
        } catch (_) {
          remaining.add(row);
        }
      }
      await store.write(
        'velo-pending-logout',
        remaining.isEmpty ? null : jsonEncode(remaining),
      );
      if (remaining.isEmpty &&
          state == AccountState.signedOut &&
          user == null) {
        _state(AccountState.signedOut);
      }
    }

    if (refreshMutex != null) {
      await refreshMutex!(flush);
    } else {
      await flush();
    }
  }

  Future<void> deleted() async {
    if (refreshMutex != null) return refreshMutex!(_deleted);
    return _deleted();
  }

  Future<void> _deleted() async {
    _authGeneration++;
    await onIdentityChange?.call(null);
    _tokens = null;
    user = null;
    await store.write('velo-session', null);
    _state(AccountState.signedOut);
  }
}

class _Unauthorized implements Exception {}
