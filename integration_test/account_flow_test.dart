import 'dart:math';

import 'package:bike_computer/services/accounts/supabase_config.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:bike_computer/main.dart' as app;
import 'package:bike_computer/core/runtime.dart';
import 'package:bike_computer/services/accounts/supabase_account_service.dart';
import 'package:bike_computer/features/accounts/account_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real Supabase account flow needs no technical configuration', (
    tester,
  ) async {
    // Historical test is only valid against a separate autoconfirm test project.
    if (VeloSupabase.url.contains('pdooxhljbutbsotbjbrt')) {
      markTestSkipped(
        'Production SMTP: use real mailbox device audit; no disposable users.',
      );
      return;
    }
    final suffix =
        '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 30)}';
    final email = 'ui-$suffix@example.invalid';
    final password = 'test-only-$suffix';
    Future<void> until(Finder finder) async {
      final deadline = DateTime.now().add(const Duration(seconds: 40));
      while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(finder, findsWidgets);
    }

    Future<void> signedIn() async {
      final deadline = DateTime.now().add(const Duration(seconds: 40));
      while (Runtime.accounts.user?['email'] != email &&
          DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(
        Runtime.accounts.user?['email'],
        email,
        reason: Runtime.accounts.message,
      );
    }

    Future<void> openAccount() async {
      await until(find.byKey(const ValueKey('tab-2')));
      await tester.tap(find.byKey(const ValueKey('tab-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('VELO-functies'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('VELO-account'));
      await tester.pumpAndSettle();
    }

    try {
      await app.main();
      final initializedDeadline = DateTime.now().add(
        const Duration(seconds: 40),
      );
      while (!Runtime.accounts.initialized &&
          DateTime.now().isBefore(initializedDeadline)) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      await tester.pumpAndSettle();
      if (find.byKey(const ValueKey('account-email')).evaluate().isEmpty) {
        await openAccount();
      }
      await until(find.byKey(const ValueKey('account-email')));
      expect(find.byKey(const ValueKey('backend-url')), findsNothing);
      await tester.tap(find.text('Nieuw account aanmaken'));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('account-name')),
        'Test rider',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('account-email')));
      await tester.enterText(
        find.byKey(const ValueKey('account-email')),
        email,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('account-password')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('account-password')),
        password,
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('account-submit')));
      await tester.tap(find.byKey(const ValueKey('account-submit')));
      await signedIn();
      await until(find.byKey(const ValueKey('tab-2')));
      expect(Runtime.accounts.user?['email'], email);
      final restored = SupabaseAccountService(
        refreshMutex: Runtime.database.withAccountRefreshLock,
      );
      await restored.restore();
      expect(restored.user?['email'], email);
      restored.dispose();
      await openAccount();
      await tester.scrollUntilVisible(
        find.text('Uitloggen'),
        250,
        scrollable: find
            .descendant(
              of: find.byType(AccountScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('Uitloggen'));
      await until(find.byKey(const ValueKey('account-email')));
      await tester.ensureVisible(find.byKey(const ValueKey('account-email')));
      await tester.enterText(
        find.byKey(const ValueKey('account-email')),
        email,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('account-password')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('account-password')),
        password,
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('account-submit')));
      await tester.tap(find.byKey(const ValueKey('account-submit')));
      await signedIn();
      await until(find.byKey(const ValueKey('tab-2')));
      expect(Runtime.accounts.user?['email'], email);
      await Runtime.accountSync.run();
      expect(Runtime.accountSync.message, isNull);
    } finally {
      if (Runtime.accounts.user?['email'] != email) {
        try {
          await Runtime.accounts.login(email, password);
        } catch (_) {}
      }
      if (Runtime.accounts.user?['email'] == email) {
        await Runtime.accounts.request(
          'DELETE',
          '/api/v1/me',
          body: {'password': password},
        );
        await Runtime.accountSync.forgetUser(Runtime.accounts.user!['id']);
        await Runtime.accounts.deleted();
      }
      await tester.pumpWidget(const SizedBox());
      Runtime.accountSync.dispose();
      Runtime.integrations.dispose();
    }
  });
}
