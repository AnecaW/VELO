import 'package:flutter/material.dart';

import '../../core/runtime.dart';
import '../../services/accounts/account_service.dart';
import '../integrations/connected_apps_screen.dart';

class AccountScreen extends StatefulWidget {
  final AccountService? account;
  const AccountScreen({super.key, this.account});
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  late final account = widget.account ?? Runtime.accounts;
  final server = TextEditingController(),
      email = TextEditingController(),
      password = TextEditingController(),
      nextPassword = TextEditingController();
  bool register = false, busy = false;
  String? message;
  @override
  void initState() {
    super.initState();
    server.text = account.base;
    account.addListener(changed);
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    account.removeListener(changed);
    for (final c in [server, email, password, nextPassword]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await action();
    } catch (e) {
      message = e is AccountFailure
          ? e.message
          : 'Verzoek mislukt. Probeer opnieuw.';
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> reset() async {
    await account.configure(server.text);
    await account.request(
      'POST',
      '/api/v1/accounts/password-reset',
      body: {'email': email.text.trim()},
      authenticated: false,
    );
    message = 'Als dit account bestaat, ontvang je instructies per e-mail.';
  }

  Future<bool> confirmDelete() async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Account verwijderen?'),
          content: const Text(
            'Alle servergegevens en koppelingen worden verwijderd. Lokale ritten blijven op dit toestel. Vul eerst je wachtwoord in.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuleren'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Verwijderen'),
            ),
          ],
        ),
      ) ??
      false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('VELO-account')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Jouw VELO', style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 12),
        const Text(
          'Je fietscomputer werkt ook zonder account. Je account en verbonden apps gebruiken je eigen VELO-server.',
        ),
        if (busy) const LinearProgressIndicator(),
        if (message ?? account.message case final String text)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(text, key: const ValueKey('account-message')),
          ),
        if (account.user == null) ...[
          TextField(
            key: const ValueKey('backend-url'),
            controller: server,
            decoration: const InputDecoration(
              labelText: 'VELO-server · https://…',
            ),
            keyboardType: TextInputType.url,
          ),
          TextField(
            key: const ValueKey('account-email'),
            controller: email,
            decoration: const InputDecoration(labelText: 'E-mailadres'),
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
          ),
          TextField(
            key: const ValueKey('account-password'),
            controller: password,
            decoration: const InputDecoration(
              labelText: 'Wachtwoord · minimaal 12 tekens',
            ),
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const ValueKey('account-submit'),
            onPressed: busy
                ? null
                : () => run(() async {
                    await account.configure(server.text);
                    await account.login(
                      email.text.trim(),
                      password.text,
                      register: register,
                    );
                    password.clear();
                  }),
            child: Text(register ? 'Account aanmaken' : 'Inloggen'),
          ),
          TextButton(
            onPressed: busy ? null : () => setState(() => register = !register),
            child: Text(
              register ? 'Ik heb al een account' : 'Nieuw account aanmaken',
            ),
          ),
          TextButton(
            onPressed: busy ? null : () => run(reset),
            child: const Text('Wachtwoord vergeten'),
          ),
        ] else ...[
          Card(
            child: ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(
                account.user?['email'] ?? account.user?['username'] ?? 'VELO',
              ),
              subtitle: Text(account.base),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const ConnectedAppsScreen(),
              ),
            ),
            child: const Text('Verbonden apps'),
          ),
          OutlinedButton(
            onPressed: busy ? null : () => run(account.restore),
            child: const Text('Verbinding opnieuw proberen'),
          ),
          TextField(
            controller: password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Huidig wachtwoord'),
          ),
          TextField(
            controller: nextPassword,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Nieuw wachtwoord · minimaal 12 tekens',
            ),
          ),
          OutlinedButton(
            onPressed: busy
                ? null
                : () => run(() async {
                    await account.request(
                      'POST',
                      '/api/v1/accounts/password',
                      body: {
                        'current_password': password.text,
                        'new_password': nextPassword.text,
                      },
                    );
                    await account.deleted();
                    password.clear();
                    nextPassword.clear();
                    message = 'Wachtwoord gewijzigd. Meld opnieuw aan.';
                  }),
            child: const Text('Wachtwoord wijzigen en sessies intrekken'),
          ),
          OutlinedButton(
            onPressed: busy
                ? null
                : () => run(() async {
                    await Runtime.integrations.strava.cache.expire(all: true);
                    await account.logout();
                  }),
            child: const Text('Uitloggen'),
          ),
          TextButton(
            onPressed: busy
                ? null
                : () => run(() async {
                    if (!await confirmDelete()) return;
                    await account.request(
                      'DELETE',
                      '/api/v1/me',
                      body: {'password': password.text},
                    );
                    await Runtime.integrations.strava.cache.expire(all: true);
                    await account.deleted();
                    password.clear();
                  }),
            child: const Text('Account verwijderen'),
          ),
        ],
      ],
    ),
  );
}
