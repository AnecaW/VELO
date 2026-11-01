import 'dart:async';
import 'dart:convert';

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
  AccountFailure(this.message);
  @override
  String toString() => message;
}

class AccountService extends ChangeNotifier {
  final TokenStore store;
  final http.Client client;
  final Future<void> Function()? onIdentityChange;
  AccountService({
    TokenStore? store,
    http.Client? client,
    this.onIdentityChange,
  }) : store = store ?? SecureTokenStore(),
       client = client ?? http.Client();
  String base = const String.fromEnvironment('VELO_BACKEND_URL');
  AccountState state = AccountState.signedOut;
  Map<String, dynamic>? user;
  String? message;
  Map<String, dynamic>? _tokens;
  Future<void>? _refreshing;
  Future<void> configure(String value) async {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path != '' && uri.path != '/') ||
        (uri.scheme != 'https' && !(kDebugMode && uri.scheme == 'http'))) {
      throw AccountFailure(
        'Gebruik een HTTPS-serveradres. HTTP is alleen toegestaan in debugbuilds.',
      );
    }
    final next = value.trim().replaceAll(RegExp(r'/+$'), '');
    if (next != base) {
      await logout();
      base = next;
    }
    await store.write('velo-backend', base);
  }

  void _state(AccountState value, [String? text]) {
    state = value;
    message = text;
    notifyListeners();
  }

  Future<void> restore() async {
    base = await store.read('velo-backend') ?? base;
    final raw = await store.read('velo-session');
    if (raw == null) return;
    try {
      _tokens = jsonDecode(raw) as Map<String, dynamic>;
      user = await request('GET', '/api/v1/me') as Map<String, dynamic>;
      _state(AccountState.signedIn);
    } catch (_) {
      /* request preserves offline credentials */
    }
  }

  Future<dynamic> _send(
    String method,
    String path,
    Object? body,
    String? token,
  ) async {
    if (base.isEmpty) {
      throw AccountFailure('Stel eerst je VELO-serveradres in.');
    }
    final uri = Uri.parse(base);
    if (uri.scheme != 'https' && !(kDebugMode && uri.scheme == 'http')) {
      throw AccountFailure('HTTPS vereist.');
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
      );
    }
    return data;
  }

  Future<void> _refresh() async {
    try {
      final next = await _send('POST', '/api/v1/accounts/refresh', {
        'refresh_token': _tokens?['refresh_token'],
      }, null);
      _tokens = Map<String, dynamic>.from(next);
      await store.write('velo-session', jsonEncode(_tokens));
    } on _Unauthorized {
      await onIdentityChange?.call();
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
      }
      try {
        final value = await _send(
          method,
          path,
          body,
          authenticated ? (_tokens!['access_token'] as String) : null,
        );
        if (authenticated) _state(AccountState.signedIn);
        return value;
      } on _Unauthorized {
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
        try {
          return await _send(method, path, body, _tokens?['access_token']);
        } on _Unauthorized {
          _state(AccountState.expired, 'Sessie verlopen. Meld opnieuw aan.');
          throw AccountFailure(message!);
        }
      }
    } on AccountFailure {
      rethrow;
    } catch (_) {
      _state(
        AccountState.unavailable,
        'VELO-server niet bereikbaar. Je fietscomputer blijft lokaal werken.',
      );
      throw AccountFailure(message!);
    }
  }

  Future<void> login(
    String email,
    String password, {
    bool register = false,
  }) async {
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
      await onIdentityChange?.call();
      user = Map<String, dynamic>.from(_tokens!['user']);
      await store.write('velo-session', jsonEncode(_tokens));
      _state(AccountState.signedIn);
    } on AccountFailure catch (e) {
      if (state == AccountState.signingIn) {
        _state(AccountState.authenticationError, e.message);
      }
      rethrow;
    }
  }

  Future<void> logout() async {
    final refresh = _tokens?['refresh_token'];
    if (refresh != null) {
      // Retain credentials when revocation cannot be confirmed; let the user retry.
      await request(
        'POST',
        '/api/v1/accounts/logout',
        body: {'refresh_token': refresh},
        authenticated: false,
      );
    }
    await onIdentityChange?.call();
    _tokens = null;
    user = null;
    await store.write('velo-session', null);
    _state(AccountState.signedOut);
  }

  Future<void> deleted() async {
    await onIdentityChange?.call();
    _tokens = null;
    user = null;
    await store.write('velo-session', null);
    _state(AccountState.signedOut);
  }
}

class _Unauthorized implements Exception {}
