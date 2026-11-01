import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bike_computer/services/accounts/account_service.dart';
import 'package:bike_computer/features/accounts/account_screen.dart';
import 'package:bike_computer/features/accounts/account_gate.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/native.dart';
import 'package:bike_computer/core/runtime.dart';
import 'package:bike_computer/database/bike_computer_database.dart';
import 'package:bike_computer/services/ride/session_codec.dart';
import 'package:bike_computer/models/ride_session.dart';

import 'accounts_sync_test.dart' show Tokens;

Map<String, dynamic> tokens({int? expiry, String refresh = 'test-refresh'}) => {
  'access_token': 'test-access',
  'refresh_token': refresh,
  'expires_at': expiry ?? DateTime.now().millisecondsSinceEpoch ~/ 1000 + 900,
  'user': {'id': 'rider', 'email': 'rider@example.test'},
};
void main() {
  test(
    'a delayed authenticated reply cannot restore signed-in state after logout',
    () async {
      final started = Completer<void>(), response = Completer<http.Response>();
      final service = AccountService(
        baseUrl: 'https://velo.example.test',
        store: Tokens(),
        client: MockClient((r) async {
          if (r.url.path.endsWith('/login')) {
            return http.Response(jsonEncode(tokens()), 200);
          }
          if (r.url.path.endsWith('/me')) {
            started.complete();
            return response.future;
          }
          return http.Response('{}', 200);
        }),
      );
      await service.login('rider@example.test', 'test-password-123');
      final pending = service.request('GET', '/api/v1/me');
      await started.future;
      await service.logout();
      response.complete(http.Response('{"id":"rider"}', 200));
      await expectLater(pending, throwsA(isA<AccountFailure>()));
      expect(service.state, AccountState.signedOut);
      expect(service.user, isNull);
    },
  );
  testWidgets('an unfinished ride cannot be assigned to a different login', (
    tester,
  ) async {
    final db = BikeComputerDatabase(executor: NativeDatabase.memory());
    Runtime.configure(db);
    await db.putDocument(
      'active',
      'ride',
      SessionCodec.encode(
        RideSession(
          state: RideState.recording,
          startTime: DateTime(2026, 11, 1),
        ),
      ),
    );
    await tester.pumpWidget(const MaterialApp(home: AccountScreen()));
    await tester.enterText(
      find.byKey(const ValueKey('account-email')),
      'rider@example.test',
    );
    await tester.enterText(
      find.byKey(const ValueKey('account-password')),
      'test-password-123',
    );
    await tester.tap(find.byKey(const ValueKey('account-submit')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Bewaar eerst je lopende rit of training voordat je van account wisselt.',
      ),
      findsOneWidget,
    );
    expect(Runtime.accounts.user, isNull);
    await tester.pumpWidget(const SizedBox());
    Runtime.configure(BikeComputerDatabase(executor: NativeDatabase.memory()));
    await db.close();
  });
  test(
    'legacy sessions retain their restored identity for the next offline open',
    () async {
      final store = Tokens();
      final legacy = tokens()..remove('user');
      store.values['velo-backend'] = 'https://velo.example.test';
      store.values['velo-session'] = jsonEncode(legacy);
      final first = AccountService(
        baseUrl: 'https://velo.example.test',
        store: store,
        client: MockClient(
          (_) async =>
              http.Response('{"id":"rider","email":"rider@example.test"}', 200),
        ),
      );
      await first.restore();
      final offline = AccountService(
        baseUrl: 'https://velo.example.test',
        store: store,
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      await offline.restore();
      expect(offline.user?['id'], 'rider');
      expect(offline.state, AccountState.unavailable);
    },
  );
  test(
    'login stores session, restores after restart and revokes logout',
    () async {
      final store = Tokens();
      var revoked = false;
      final client = MockClient((r) async {
        if (r.url.path.endsWith('/login')) {
          return http.Response(jsonEncode(tokens()), 200);
        }
        if (r.url.path.endsWith('/logout')) {
          revoked = true;
          return http.Response('{}', 200);
        }
        expect(r.headers['Authorization'], 'Bearer test-access');
        return http.Response(
          '{"id":"rider","email":"rider@example.test"}',
          200,
        );
      });
      final first = AccountService(
        baseUrl: 'https://velo.example.test',
        store: store,
        client: client,
      );
      await first.login('rider@example.test', 'test-password-123');
      expect(first.state, AccountState.signedIn);
      expect(store.values['velo-session'], isNotNull);
      final restored = AccountService(
        baseUrl: 'https://velo.example.test',
        store: store,
        client: client,
      );
      await restored.restore();
      expect(restored.user?['id'], 'rider');
      await restored.logout();
      expect(revoked, isTrue);
      expect(store.values['velo-session'], isNull);
    },
  );
  test('expired access rotates once for simultaneous requests', () async {
    final store = Tokens();
    var refreshes = 0;
    store.values['velo-backend'] = 'https://velo.example.test';
    store.values['velo-session'] = jsonEncode(tokens(expiry: 1));
    final service = AccountService(
      baseUrl: 'https://velo.example.test',
      store: store,
      client: MockClient((r) async {
        if (r.url.path.endsWith('/refresh')) {
          refreshes++;
          return http.Response(jsonEncode(tokens(refresh: 'rotated')), 200);
        }
        return http.Response('{"id":"rider"}', 200);
      }),
    );
    await service.restore();
    await Future.wait([
      service.request('GET', '/api/v1/me'),
      service.request('GET', '/api/v1/me'),
    ]);
    expect(refreshes, 1);
    expect(store.values['velo-session'], contains('rotated'));
  });
  test(
    'offline restore preserves secure credentials and reports unavailable',
    () async {
      final store = Tokens();
      store.values['velo-backend'] = 'https://velo.example.test';
      store.values['velo-session'] = jsonEncode(tokens());
      final service = AccountService(
        baseUrl: 'https://velo.example.test',
        store: store,
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      await service.restore();
      expect(service.state, AccountState.unavailable);
      expect(store.values['velo-session'], isNotNull);
    },
  );
  test('revoked refresh clears credentials and reports expired', () async {
    final store = Tokens();
    store.values['velo-backend'] = 'https://velo.example.test';
    store.values['velo-session'] = jsonEncode(tokens(expiry: 1));
    final service = AccountService(
      baseUrl: 'https://velo.example.test',
      store: store,
      client: MockClient(
        (_) async => http.Response('{"error":{"code":"session_expired"}}', 401),
      ),
    );
    await service.restore();
    expect(service.state, AccountState.expired);
    expect(store.values['velo-session'], isNull);
  });
  testWidgets('email login form and registration switch', (tester) async {
    final service = AccountService(
      baseUrl: 'https://velo.example.test',
      store: Tokens(),
      client: MockClient(
        (_) async => http.Response('{"error":{"message":"Fout"}}', 400),
      ),
    );
    await tester.pumpWidget(MaterialApp(home: AccountScreen(account: service)));
    expect(find.byKey(const ValueKey('account-email')), findsOneWidget);
    expect(find.text('Inloggen'), findsOneWidget);
    await tester.tap(find.text('Nieuw account aanmaken'));
    await tester.pump();
    expect(find.text('Account aanmaken'), findsOneWidget);
    expect(find.text('Wachtwoord vergeten'), findsOneWidget);
    expect(find.byKey(const ValueKey('backend-url')), findsNothing);
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('first open signs in without asking for connection settings', (
    tester,
  ) async {
    final service = AccountService(
      baseUrl: 'https://velo.example.test',
      store: Tokens(),
      client: MockClient(
        (request) async => http.Response(jsonEncode(tokens()), 200),
      ),
    );
    await service.restore();
    final testRouter = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('Klaar om te fietsen')),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: testRouter,
        builder: (context, child) =>
            AccountGate(account: service, child: child!),
      ),
    );
    expect(find.text('Inloggen'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('account-email')),
      'rider@example.test',
    );
    await tester.enterText(
      find.byKey(const ValueKey('account-password')),
      'test-password-123',
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('account-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Klaar om te fietsen'), findsOneWidget);
    expect(service.state, AccountState.signedIn);
    await tester.pumpWidget(const SizedBox());
    testRouter.dispose();
  });

  testWidgets('local bike computer remains accessible without signing in', (
    tester,
  ) async {
    final service = AccountService(
      baseUrl: 'https://velo.example.test',
      store: Tokens(),
      client: MockClient((_) async => throw http.ClientException('offline')),
    );
    await service.restore();
    await tester.pumpWidget(
      MaterialApp(
        home: AccountGate(
          account: service,
          child: const Scaffold(body: Text('Lokale fietscomputer')),
        ),
      ),
    );
    await tester.tap(find.text('Verder zonder account'));
    await tester.pumpAndSettle();
    expect(find.text('Lokale fietscomputer'), findsOneWidget);
  });

  test('a previous backend preference cannot redirect the internally configured app', () async {
    final store = Tokens();
    store.values['velo-backend'] = 'https://other.example.test';
    store.values['velo-session'] = jsonEncode(tokens());
    var sent = false;
    final service = AccountService(
      baseUrl: 'https://velo.example.test',
      store: store,
      client: MockClient((_) async {
        sent = true;
        return http.Response('{}', 200);
      }),
    );
    await service.restore();
    expect(service.base, 'https://velo.example.test');
    expect(sent, isFalse);
    expect(store.values['velo-session'], isNull);
  });
}
