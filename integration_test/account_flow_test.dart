import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:bike_computer/main.dart' as app;
import 'package:bike_computer/core/runtime.dart';
import 'package:bike_computer/services/accounts/account_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real LAN account flow needs no technical configuration', (
    tester,
  ) async {
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

    Future<void> openAccount() async {
      await until(find.byKey(const ValueKey('tab-4')));
      await tester.tap(find.byKey(const ValueKey('tab-4')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('VELO-account'));
      await tester.pumpAndSettle();
    }

    try {
      await app.main();
      await until(find.byKey(const ValueKey('account-email')));
      expect(find.byKey(const ValueKey('backend-url')), findsNothing);
      await tester.tap(find.text('Nieuw account aanmaken'));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('account-email')),
        email,
      );
      await tester.enterText(
        find.byKey(const ValueKey('account-password')),
        password,
      );
      await tester.tap(find.byKey(const ValueKey('account-submit')));
      await until(find.byKey(const ValueKey('tab-4')));
      expect(Runtime.accounts.user?['email'], email);
      final restored = AccountService(
        refreshMutex: Runtime.database.withAccountRefreshLock,
      );
      await restored.restore();
      expect(restored.user?['email'], email);
      restored.dispose();
      await openAccount();
      await tester.ensureVisible(find.text('Uitloggen'));
      await tester.tap(find.text('Uitloggen'));
      await until(find.byKey(const ValueKey('account-email')));
      await tester.enterText(
        find.byKey(const ValueKey('account-email')),
        email,
      );
      await tester.enterText(
        find.byKey(const ValueKey('account-password')),
        password,
      );
      await tester.tap(find.byKey(const ValueKey('account-submit')));
      await until(find.byKey(const ValueKey('tab-4')));
      expect(Runtime.accounts.user?['email'], email);
      await Runtime.accountSync.run();
      expect(Runtime.accountSync.message, isNull);
    } finally {
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
