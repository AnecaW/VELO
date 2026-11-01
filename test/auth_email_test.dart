import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bike_computer/services/accounts/account_service.dart';
import 'package:bike_computer/services/accounts/supabase_account_service.dart';
import 'package:bike_computer/services/accounts/supabase_config.dart';
import 'package:bike_computer/features/accounts/account_gate.dart';
import 'package:bike_computer/features/accounts/password_screens.dart';

import 'accounts_sync_test.dart' show Tokens;
import 'supabase_accounts_test.dart' show session;

void main() {
  test('SDK submits display name and waits for email confirmation; resend uses signup type', () async {
    final requests = <http.Request>[];
    final store = Tokens();
    final sdk = SupabaseClient(
      VeloSupabase.url,
      VeloSupabase.publishableKey,
      authOptions: AuthClientOptions(
        autoRefreshToken: false,
        pkceAsyncStorage: SecurePkceStorage(store),
      ),
      httpClient: MockClient((r) async {
        requests.add(r);
        return http.Response(
          jsonEncode(r.url.path.endsWith('/signup') ? session()['user'] : {}),
          200,
          request: r,
        );
      }),
    );
    final account = SupabaseAccountService(supabase: sdk, store: store);
    await account.registerAccount(
      '  Wannes  ',
      'rider@example.test',
      'test-password-123',
    );
    expect(jsonDecode(requests.first.body)['data']['display_name'], 'Wannes');
    expect(
      requests.first.url.queryParameters['redirect_to'],
      VeloSupabase.redirect,
    );
    expect(account.user, isNull);
    expect(account.state, AccountState.signedOut);
    expect(account.confirmationEmail, 'rider@example.test');
    expect(store.values[SecureSupabaseStorage.key], isNull);
    await account.resendVerification('rider@example.test');
    expect(requests.last.url.path, endsWith('/resend'));
    expect(jsonDecode(requests.last.body)['type'], 'signup');
    account.dispose();
    await sdk.dispose();
  });
  test('unconfirmed email cannot acquire a signed-in account', () async {
    final sdk = SupabaseClient(
      VeloSupabase.url,
      VeloSupabase.publishableKey,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(
        (r) async => http.Response(
          '{"code":"email_not_confirmed","msg":"Email not confirmed"}',
          400,
          request: r,
          headers: {'x-supabase-api-version': '2024-01-01'},
        ),
      ),
    );
    final account = SupabaseAccountService(supabase: sdk, store: Tokens());
    await expectLater(
      account.login('rider@example.test', 'test-password-123'),
      throwsA(isA<AccountFailure>()),
    );
    expect(account.user, isNull);
    expect(account.confirmationEmail, 'rider@example.test');
    await expectLater(
      account.completePasswordRecovery('test-password-123'),
      throwsA(isA<AccountFailure>()),
    );
    account.dispose();
    await sdk.dispose();
  });
  test(
    'password recovery delegates to official SDK with canonical deep link',
    () async {
      final requests = <http.Request>[];
      final store = Tokens();
      final sdk = SupabaseClient(
        VeloSupabase.url,
        VeloSupabase.publishableKey,
        authOptions: AuthClientOptions(
          autoRefreshToken: false,
          pkceAsyncStorage: SecurePkceStorage(store),
        ),
        httpClient: MockClient((r) async {
          requests.add(r);
          return http.Response(
            r.url.path.contains('/functions/')
                ? '{"password_reset_enabled":true}'
                : '{}',
            200,
            request: r,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final account = SupabaseAccountService(supabase: sdk, store: store);
      await account.request(
        'POST',
        '/api/v1/accounts/password-reset',
        body: {'email': 'rider@example.test'},
        authenticated: false,
      );
      final reset = requests.singleWhere(
        (r) => r.url.path.endsWith('/recover'),
      );
      expect(reset.url.queryParameters['redirect_to'], VeloSupabase.redirect);
      expect(jsonDecode(reset.body)['email'], 'rider@example.test');
      account.dispose();
      await sdk.dispose();
    },
  );
  test('email recovery code creates recovery session and password update revokes it', () async {
    final calls = <http.Request>[];
    final sdk = SupabaseClient(
      VeloSupabase.url,
      VeloSupabase.publishableKey,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((r) async {
        calls.add(r);
        return http.Response(
          jsonEncode(
            r.url.path.endsWith('/verify')
                ? session()
                : r.url.path.endsWith('/user')
                ? session()['user']
                : {},
          ),
          200,
          request: r,
        );
      }),
    );
    final store = Tokens();
    final account = SupabaseAccountService(supabase: sdk, store: store);
    await account.verifyEmailCode(
      'rider@example.test',
      '123456',
      recovery: true,
    );
    expect(account.passwordRecovery, isTrue);
    expect(jsonDecode(calls.first.body)['type'], 'recovery');
    expect(account.user?['id'], isNotNull);
    await account.completePasswordRecovery('new-test-password-123');
    expect(
      calls.any((r) => r.method == 'PUT' && r.url.path.endsWith('/user')),
      isTrue,
    );
    expect(
      calls.any(
        (r) =>
            r.url.path.endsWith('/logout') &&
            r.url.queryParameters['scope'] == 'global',
      ),
      isTrue,
    );
    expect(account.passwordRecovery, isFalse);
    expect(account.user, isNull);
    account.dispose();
    await sdk.dispose();
  });
  testWidgets('expired link blocks normal gate and dismiss returns to login', (
    tester,
  ) async {
    final account =
        AccountService(baseUrl: 'https://example.test', store: Tokens())
          ..initialized = true
          ..authLinkError = 'Deze link is verlopen.';
    await tester.pumpWidget(
      MaterialApp(
        home: AccountGate(account: account, child: const Text('fiets')),
      ),
    );
    expect(find.text('Link niet beschikbaar'), findsOneWidget);
    await tester.tap(find.text('Terug naar VELO'));
    await tester.pumpAndSettle();
    expect(find.text('Inloggen'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    account.dispose();
  });
  testWidgets('new password validates length and matching confirmation', (
    tester,
  ) async {
    final account = AccountService(
      baseUrl: 'https://example.test',
      store: Tokens(),
    );
    await tester.pumpWidget(
      MaterialApp(home: PasswordRecoveryScreen(account: account)),
    );
    await tester.tap(find.text('Nieuw wachtwoord opslaan'));
    await tester.pump();
    expect(find.text('Gebruik minimaal 12 tekens.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('recovery-password')),
      'long-password-123',
    );
    await tester.enterText(
      find.byKey(const ValueKey('recovery-confirm')),
      'different-password',
    );
    await tester.ensureVisible(find.text('Nieuw wachtwoord opslaan'));
    await tester.tap(find.text('Nieuw wachtwoord opslaan'));
    await tester.pump();
    expect(find.text('De wachtwoorden komen niet overeen.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    account.dispose();
  });
}
