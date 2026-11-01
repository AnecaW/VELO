import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bike_computer/services/accounts/account_service.dart';
import 'package:bike_computer/services/accounts/supabase_account_service.dart';
import 'package:bike_computer/services/accounts/supabase_config.dart';

import 'accounts_sync_test.dart' show Tokens;

const riderId = '11111111-1111-4111-8111-111111111111';
Map<String, dynamic> session({int? expiry}) {
  final exp = expiry ?? DateTime.now().millisecondsSinceEpoch ~/ 1000 + 900;
  String encode(Object v) =>
      base64UrlEncode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
  return {
    'access_token':
        '${encode({'alg': 'HS256'})}.${encode({'sub': riderId, 'exp': exp})}.signature',
    'token_type': 'bearer',
    'refresh_token': 'test-refresh',
    'expires_in': 900,
    'expires_at': exp,
    'user': {
      'id': riderId,
      'email': 'rider@example.test',
      'aud': 'authenticated',
      'app_metadata': {},
      'user_metadata': {},
      'created_at': '2026-11-01T00:00:00Z',
    },
  };
}

void main() {
  test('revoked SDK refresh clears secure credentials and reports an expired session', () async {
    final store = Tokens();
    final expired = session(
      expiry: DateTime.now().millisecondsSinceEpoch ~/ 1000 - 60,
    );
    final sdk = SupabaseClient(
      VeloSupabase.url,
      VeloSupabase.publishableKey,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(
        (r) async => http.Response(
          '{"code":"refresh_token_not_found","msg":"Invalid refresh token"}',
          400,
          request: r,
        ),
      ),
    );
    await sdk.auth.setInitialSession(jsonEncode(expired));
    await store.write(SecureSupabaseStorage.key, jsonEncode(expired));
    final account = SupabaseAccountService(supabase: sdk, store: store);
    await account.restore();
    expect(account.state, AccountState.expired);
    expect(account.user, isNull);
    expect(store.values[SecureSupabaseStorage.key], isNull);
    account.dispose();
    await sdk.dispose();
  });

  test('official SDK registration, secure persistence, restore, RPC sync and logout', () async {
    final store = Tokens();
    final requests = <http.Request>[];
    final transport = MockClient((r) async {
      requests.add(r);
      expect(r.url.host, 'pdooxhljbutbsotbjbrt.supabase.co');
      if (r.url.path.endsWith('/signup') || r.url.path.endsWith('/token')) {
        return http.Response(jsonEncode(session()), 200, request: r);
      }
      if (r.url.path.endsWith('/user')) {
        return http.Response(jsonEncode(session()['user']), 200, request: r);
      }
      if (r.url.path.endsWith('/velo_write_document')) {
        final body = jsonDecode(r.body);
        expect(body['p_id'], 'A/B? café');
        expect(body.containsKey('user_id'), isFalse);
        return http.Response(
          '{"revision":12}',
          200,
          request: r,
          headers: {'content-type': 'application/json'},
        );
      }
      if (r.url.path.endsWith('/velo_documents_page')) {
        return http.Response(
          '{"items":[],"cursor":12,"has_more":false}',
          200,
          request: r,
        );
      }
      return http.Response(
        '{}',
        200,
        request: r,
        headers: {'content-type': 'application/json'},
      );
    });
    SupabaseClient sdk() => SupabaseClient(
      VeloSupabase.url,
      VeloSupabase.publishableKey,
      httpClient: transport,
      authOptions: AuthClientOptions(
        autoRefreshToken: false,
        pkceAsyncStorage: SecurePkceStorage(store),
      ),
    );
    final firstSdk = sdk();
    final owners = <String?>[];
    final first = SupabaseAccountService(
      supabase: firstSdk,
      store: store,
      onIdentityChange: (id) async {
        owners.add(id);
      },
    );
    await first.login(
      'rider@example.test',
      'test-password-123',
      register: true,
    );
    expect(first.state, AccountState.signedIn);
    expect(first.user?['id'], riderId);
    expect(store.values[SecureSupabaseStorage.key], contains('test-refresh'));
    expect(first.localNetworkOnly, isFalse);
    final secondSdk = sdk();
    final restored = SupabaseAccountService(supabase: secondSdk, store: store);
    await restored.restore();
    expect(restored.user?['id'], riderId);
    final saved = await restored.request(
      'PUT',
      '/api/v1/data/routes/A%2FB%3F%20caf%C3%A9',
      body: {
        'payload': {'name': 'Route'},
      },
    );
    expect(saved['revision'], 12);
    final page = await restored.request(
      'GET',
      '/api/v1/data/routes?after=0&include_deleted=true',
    );
    expect(page['cursor'], 12);
    await first.logout();
    expect(first.user, isNull);
    expect(owners.last, isNull);
    expect(store.values[SecureSupabaseStorage.key], isNull);
    await expectLater(
      restored.request('GET', '/api/v1/me'),
      throwsA(isA<AccountFailure>()),
    );
    expect(requests.any((r) => r.url.path.contains('/api/v1/')), isFalse);
    first.dispose();
    restored.dispose();
    await firstSdk.dispose();
    await secondSdk.dispose();
  });
  test(
    'wrong password has a friendly error and never creates a session',
    () async {
      final sdk = SupabaseClient(
        VeloSupabase.url,
        VeloSupabase.publishableKey,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient(
          (_) async => http.Response(
            '{"code":"invalid_credentials","msg":"Invalid login credentials"}',
            400,
          ),
        ),
      );
      final service = SupabaseAccountService(supabase: sdk, store: Tokens());
      await expectLater(
        service.login('rider@example.test', 'wrong-password'),
        throwsA(isA<AccountFailure>()),
      );
      expect(service.state, AccountState.authenticationError);
      expect(service.user, isNull);
      service.dispose();
      await sdk.dispose();
    },
  );
  test(
    'secure SDK storage and PKCE verifier do not use ordinary preferences',
    () async {
      final tokens = Tokens();
      final storage = SecureSupabaseStorage(tokens);
      final pkce = SecurePkceStorage(tokens);
      await storage.initialize();
      await storage.persistSession('sensitive-session');
      await pkce.setItem(key: 'verifier', value: 'sensitive-proof');
      expect(await storage.accessToken(), 'sensitive-session');
      expect(await pkce.getItem(key: 'verifier'), 'sensitive-proof');
      await storage.removePersistedSession();
      await pkce.removeItem(key: 'verifier');
      expect(await storage.hasAccessToken(), isFalse);
      expect(await pkce.getItem(key: 'verifier'), isNull);
    },
  );
}
