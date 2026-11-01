import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'account_service.dart';
import 'supabase_config.dart';

/// Keeps the existing UI and offline sync contract, backed only by Supabase.
class SupabaseAccountService extends AccountService {
  SupabaseAccountService({
    super.store,
    super.onIdentityChange,
    super.refreshMutex,
    this.supabase,
    this.onLegacyIdentity,
    this.background = false,
  }) : super(baseUrl: VeloSupabase.url);
  final SupabaseClient? supabase;
  final bool background;
  final Future<void> Function(String previous, String owner)? onLegacyIdentity;
  SupabaseClient? _supabase;
  StreamSubscription<AuthState>? _events;
  Future<void> _identityQueue = Future.value();
  int _generation = 0;
  bool recovery = false;
  bool _explicitAuth = false;
  String? _signupName;
  @override
  bool get passwordRecovery => recovery;
  @override
  bool get localNetworkOnly => false;

  Future<SupabaseClient> _sdk() async {
    final sdk = _supabase ??=
        supabase ?? await VeloSupabase.initialize(background: background);
    _events ??= sdk.auth.onAuthStateChange.listen(
      (event) {
        if (_explicitAuth) return;
        if (event.event == AuthChangeEvent.passwordRecovery) {
          recovery = true;
          authLinkError = null;
          _generation++;
          _identityQueue = _identityQueue
              .then((_) => _adopt(event.session))
              .catchError((Object _) {
                _state(
                  AccountState.unavailable,
                  'Je account kon niet worden geopend. Probeer opnieuw.',
                );
              });
        } else if (event.event == AuthChangeEvent.signedIn &&
            event.session != null) {
          confirmationEmail = null;
          authLinkError = null;
          _generation++;
          _identityQueue = _identityQueue
              .then((_) => _adopt(event.session))
              .catchError((Object _) {});
        }
      },
      onError: (Object e) {
        if (e is AuthException &&
            [
              'otp_expired',
              'flow_state_expired',
              'flow_state_not_found',
              'bad_code_verifier',
              'bad_jwt',
              'validation_failed',
              'unexpected_failure',
            ].any((code) => code == e.code || code == e.statusCode)) {
          authLinkError = 'Deze link is ongeldig of verlopen. Vraag een nieuwe e-mail aan en open de link op dit toestel.';
          notifyListeners();
        }
      },
    );
    return sdk;
  }

  void _state(AccountState next, [String? text]) {
    state = next;
    message = text;
    notifyListeners();
  }

  Future<void> _adopt(Session? session) async {
    final next = session?.user;
    await onIdentityChange?.call(next?.id);
    user = next == null
        ? null
        : {
            'id': next.id,
            'email': next.email,
            'created_at': next.createdAt,
            'name': next.userMetadata?['display_name'],
          };
    initialized = true;
    _state(next == null ? AccountState.signedOut : AccountState.signedIn);
  }

  Future<T> _locked<T>(Future<T> Function() action) async {
    if (refreshMutex == null) return action();
    late T result;
    await refreshMutex!(() async {
      result = await action();
    });
    return result;
  }

  Future<Session?> _session(SupabaseClient sdk) => _locked(() async {
    final saved = await store.read(SecureSupabaseStorage.key);
    if (saved != null) {
      final stored = jsonDecode(saved) as Map<String, dynamic>;
      if (sdk.auth.currentUser != null &&
          stored['user']?['id'] != sdk.auth.currentUser!.id) {
        throw AccountFailure(
          'Je account is gewijzigd. Open VELO opnieuw.',
          code: 'session_changed',
        );
      }
      if (stored['refresh_token'] != sdk.auth.currentSession?.refreshToken) {
        await sdk.auth.recoverSession(saved);
      }
    } else if (sdk.auth.currentSession != null && user != null) {
      throw AccountFailure('Je sessie is beëindigd. Meld opnieuw aan.');
    }
    var session = sdk.auth.currentSession;
    if (session != null &&
        (session.expiresAt ?? 0) <=
            DateTime.now().millisecondsSinceEpoch ~/ 1000 + 30) {
      try {
        session = (await sdk.auth.refreshSession()).session;
      } on AuthException catch (e) {
        if (e is AuthRetryableFetchException) rethrow;
        _generation++;
        try {
          await sdk.auth
              .signOut(scope: SignOutScope.local)
              .timeout(const Duration(seconds: 10));
        } catch (_) {}
        await store.write(SecureSupabaseStorage.key, null);
        await _adopt(null);
        _state(
          AccountState.expired,
          'Je sessie is verlopen. Meld je opnieuw aan.',
        );
        throw AccountFailure(message!, code: 'session_expired');
      }
      if (session != null) {
        await store.write(
          SecureSupabaseStorage.key,
          jsonEncode(session.toJson()),
        );
      }
    }
    return session;
  });
  AccountFailure _failure(Object e) {
    if (e is AccountFailure) return e;
    if (e is AuthException) {
      if (e is AuthRetryableFetchException) {
        _state(
          AccountState.unavailable,
          'Geen verbinding met VELO. Je fietscomputer blijft werken.',
        );
      } else {
        _state(
          AccountState.authenticationError,
          e.code == 'email_not_confirmed'
              ? 'Bevestig eerst je e-mailadres.'
              : e.statusCode == '429'
              ? 'Te veel pogingen. Probeer het later opnieuw.'
              : 'Aanmelden mislukt. Controleer je gegevens en probeer opnieuw.',
        );
      }
      return AccountFailure(message!, code: e.code);
    }
    if (e is PostgrestException) {
      return AccountFailure(
        (e.code == '40001' || e.code == 'PT409')
            ? 'Je gegevens zijn elders gewijzigd. Synchroniseer opnieuw.'
            : 'Opslaan bij VELO is tijdelijk niet mogelijk. Je gegevens blijven lokaal bewaard.',
        status: (e.code == '40001' || e.code == 'PT409') ? 409 : null,
        code: e.code,
      );
    }
    if (e is FunctionException) {
      final details = e.details;
      return AccountFailure(
        details is Map
            ? (details['error']?['message'] ?? 'Verzoek mislukt.')
            : 'Verzoek mislukt.',
        status: e.status,
      );
    }
    _state(
      AccountState.unavailable,
      'Geen verbinding met VELO. Je fietscomputer blijft werken.',
    );
    return AccountFailure(message!);
  }

  @override
  Future<void> restore() async {
    final generation = _generation;
    try {
      final sdk = await _sdk();
      if (generation != _generation) return;
      final existing = sdk.auth.currentSession;
      if (existing != null) await _adopt(existing);
      final session = await _session(sdk);
      if (generation != _generation) return;
      if (session != null) {
        await _adopt(session);
        await sdk.auth.getUser();
        if (generation != _generation) return;
        await _adopt(session);
      } else {
        await _adopt(null);
      }
      await flushPendingLogouts();
    } catch (e) {
      if (e is AuthException && e is! AuthRetryableFetchException) {
        _generation++;
        final sdk = await _sdk();
        try {
          await sdk.auth
              .signOut(scope: SignOutScope.local)
              .timeout(const Duration(seconds: 10));
        } catch (_) {}
        await store.write(SecureSupabaseStorage.key, null);
        await _adopt(null);
        _state(
          AccountState.expired,
          'Je sessie is verlopen. Meld je opnieuw aan.',
        );
      } else {
        _failure(e);
      }
    } finally {
      initialized = true;
      notifyListeners();
    }
  }

  @override
  Future<void> login(
    String email,
    String password, {
    bool register = false,
  }) async {
    _generation++;
    _explicitAuth = true;
    confirmationEmail = null;
    _state(AccountState.signingIn);
    try {
      final sdk = await _sdk();
      await _locked(() async {
        final result = register
            ? await sdk.auth.signUp(
                email: email.trim(),
                password: password,
                emailRedirectTo: VeloSupabase.redirect,
                data: {'display_name': _signupName ?? ''},
              )
            : await sdk.auth.signInWithPassword(
                email: email.trim(),
                password: password,
              );
        if (result.session == null) {
          confirmationEmail = email.trim();
          _state(
            AccountState.signedOut,
            'Controleer je e-mail om je account te bevestigen.',
          );
          return;
        }
        await store.write(
          SecureSupabaseStorage.key,
          jsonEncode(result.session!.toJson()),
        );
        await _adopt(result.session);
        final legacyRaw = await store.read('velo-session');
        if (legacyRaw != null) {
          final legacy = jsonDecode(legacyRaw);
          final oldUser = legacy['user'];
          if (oldUser is Map &&
              oldUser['id'] is String &&
              (oldUser['email'] as String?)?.toLowerCase() ==
                  result.user?.email?.toLowerCase()) {
            await onLegacyIdentity?.call(oldUser['id'], result.user!.id);
            await store.write('velo-session', null);
          }
        }
      });
    } catch (e) {
      if (e is AuthException && e.code == 'email_not_confirmed') {
        confirmationEmail = email.trim();
      }
      throw _failure(e);
    } finally {
      _explicitAuth = false;
    }
  }

  @override
  Future<void> registerAccount(
    String name,
    String email,
    String password,
  ) async {
    _signupName = name.trim();
    try {
      await login(email, password, register: true);
    } finally {
      _signupName = null;
    }
  }

  @override
  Future<void> verifyEmailCode(
    String email,
    String code, {
    bool recovery = false,
  }) async {
    if (!RegExp(r'^\d{6,10}$').hasMatch(code.trim())) {
      throw AccountFailure('Vul de code uit je e-mail in.');
    }
    try {
      _explicitAuth = true;
      final result = await (await _sdk()).auth
          .verifyOTP(
            email: email.trim(),
            token: code.trim(),
            type: recovery ? OtpType.recovery : OtpType.email,
          )
          .timeout(const Duration(seconds: 20));
      if (result.session == null) {
        throw AccountFailure('Vraag een nieuwe code aan.');
      }
      this.recovery = recovery;
      authLinkError = null;
      confirmationEmail = null;
      _generation++;
      await store.write(
        SecureSupabaseStorage.key,
        jsonEncode(result.session!.toJson()),
      );
      await _adopt(result.session);
    } on TimeoutException {
      throw AccountFailure('Geen verbinding met VELO. Probeer opnieuw.');
    } on AuthRetryableFetchException {
      throw AccountFailure('Geen verbinding met VELO. Probeer opnieuw.');
    } on AuthException {
      throw AccountFailure(
        'Deze code is onjuist of verlopen. Vraag indien nodig een nieuwe mail aan.',
      );
    } finally {
      _explicitAuth = false;
    }
  }

  @override
  Future<void> resendVerification(String email) async {
    try {
      await (await _sdk()).auth.resend(
        type: OtpType.signup,
        email: email.trim(),
        emailRedirectTo: VeloSupabase.redirect,
      );
    } catch (e) {
      throw _failure(e);
    }
  }

  @override
  Future<void> completePasswordRecovery(String password) async {
    if (!recovery) throw AccountFailure('Open eerst een geldige herstelmail.');
    if (password.length < 12) {
      throw AccountFailure('Gebruik minimaal 12 tekens.');
    }
    try {
      final sdk = await _sdk();
      await sdk.auth.updateUser(UserAttributes(password: password));
      await sdk.auth.signOut(scope: SignOutScope.global);
      await deleted();
    } catch (e) {
      throw _failure(e);
    }
  }

  @override
  Future<void> logout() async {
    _generation++;
    final sdk = await _sdk();
    await _locked(() async {
      final raw = await store.read(SecureSupabaseStorage.key);
      if (raw != null) {
        final saved = jsonDecode(raw);
        if (user != null && saved['user']?['id'] != user!['id']) {
          throw AccountFailure(
            'Je account is gewijzigd.',
            code: 'session_changed',
          );
        }
        if (saved['refresh_token'] != sdk.auth.currentSession?.refreshToken) {
          await sdk.auth.recoverSession(raw);
        }
      }
      final session = sdk.auth.currentSession;
      try {
        await sdk.auth.signOut(scope: SignOutScope.local);
      } catch (_) {
        if (session != null) {
          await store.write(
            'velo-supabase-pending-logout',
            jsonEncode(session.toJson()),
          );
        }
      }
      await store.write(SecureSupabaseStorage.key, null);
      recovery = false;
      await _adopt(null);
      _generation++;
    });
  }

  @override
  Future<void> flushPendingLogouts() async {
    final raw = await store.read('velo-supabase-pending-logout');
    if (raw == null) return;
    // Use an isolated client: revoking an old session must not replace the new one.
    final isolated = SupabaseClient(
      VeloSupabase.url,
      VeloSupabase.publishableKey,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    try {
      await isolated.auth.recoverSession(raw);
      await isolated.auth.signOut(scope: SignOutScope.local);
      await store.write('velo-supabase-pending-logout', null);
    } on AuthException catch (e) {
      if (e is! AuthRetryableFetchException) {
        await store.write('velo-supabase-pending-logout', null);
      }
    } finally {
      await isolated.dispose();
    }
  }

  @override
  Future<void> deleted() async {
    _generation++;
    final sdk = await _sdk();
    await _locked(() async {
      try {
        await sdk.auth.signOut(scope: SignOutScope.local);
      } catch (_) {}
      await store.write(SecureSupabaseStorage.key, null);
      recovery = false;
      await _adopt(null);
      _generation++;
    });
  }

  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    bool authenticated = true,
  }) async {
    final generation = _generation;
    try {
      final sdk = await _sdk();
      if (authenticated && await _session(sdk) == null) {
        _state(AccountState.expired, 'Meld je opnieuw aan.');
        throw AccountFailure(message!);
      }
      if (generation != _generation ||
          (authenticated &&
              user != null &&
              sdk.auth.currentUser?.id != user!['id'])) {
        throw AccountFailure(
          'Je account is gewijzigd.',
          code: 'session_changed',
        );
      }
      final uri = Uri.parse(path);
      final data = body is Map ? body : <String, dynamic>{};
      dynamic value;
      if (path == '/api/v1/accounts/password-reset') {
        final config = (await sdk.functions.invoke(
          'velo-api/config',
          method: HttpMethod.get,
        )).data;
        if (config is! Map || config['password_reset_enabled'] != true) {
          throw AccountFailure(
            'Wachtwoordherstel is nog niet beschikbaar. Neem contact op met de beheerder.',
          );
        }
        await sdk.auth.resetPasswordForEmail(
          data['email'],
          redirectTo: VeloSupabase.redirect,
        );
        value = {'ok': true};
      } else if (path == '/api/v1/accounts/password') {
        if ((data['new_password'] as String? ?? '').length < 12) {
          throw AccountFailure(
            'Gebruik een wachtwoord van minimaal 12 tekens.',
          );
        }
        if (!recovery) {
          await sdk.auth.signInWithPassword(
            email: user!['email'],
            password: data['current_password'],
          );
        }
        await sdk.auth.updateUser(
          UserAttributes(password: data['new_password']),
        );
        await sdk.auth.signOut(scope: SignOutScope.global);
        value = {'ok': true};
      } else if (path == '/api/v1/me' && method == 'GET') {
        final u = (await sdk.auth.getUser()).user!;
        value = {'id': u.id, 'email': u.email, 'created_at': u.createdAt};
      } else if (uri.path.startsWith('/api/v1/data/')) {
        final parts = uri.pathSegments;
        final kind = parts[3];
        if (method == 'GET') {
          value = await sdk.rpc(
            'velo_documents_page',
            params: {
              'p_kind': kind,
              'p_after': int.tryParse(uri.queryParameters['after'] ?? '0') ?? 0,
            },
          );
        } else {
          value = await sdk.rpc(
            'velo_write_document',
            params: {
              'p_kind': kind,
              'p_id': parts.sublist(4).join('/'),
              'p_payload': method == 'DELETE' ? null : data['payload'],
              'p_expected_revision': method == 'DELETE'
                  ? int.tryParse(uri.queryParameters['expected_revision'] ?? '')
                  : data['expected_revision'],
            },
          );
        }
      } else {
        value = (await sdk.functions.invoke(
          'velo-api',
          body: {'method': method, 'path': path, 'body': body},
        )).data;
      }
      if (generation != _generation) {
        throw AccountFailure(
          'Je account is gewijzigd.',
          code: 'session_changed',
        );
      }
      if (authenticated) _state(AccountState.signedIn);
      return value;
    } catch (e) {
      throw _failure(e);
    }
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }
}
