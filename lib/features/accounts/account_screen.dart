import 'package:flutter/material.dart';

import 'dart:convert';

import '../../core/runtime.dart';
import '../../services/accounts/account_service.dart';
import '../integrations/connected_apps_screen.dart';

class AccountScreen extends StatefulWidget {
  final AccountService? account;
  final VoidCallback? onContinueOffline;
  const AccountScreen({super.key, this.account, this.onContinueOffline});
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  late final account = widget.account ?? Runtime.accounts;
  final email = TextEditingController(),
      password = TextEditingController(),
      nextPassword = TextEditingController();
  bool register = false, busy = false;
  bool get uiBusy => busy || account.state == AccountState.signingIn;
  String? message;
  @override
  void initState() {
    super.initState();
    account.addListener(changed);
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    account.removeListener(changed);
    for (final c in [email, password, nextPassword]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
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
    await account.request(
      'POST',
      '/api/v1/accounts/password-reset',
      body: {'email': email.text.trim()},
      authenticated: false,
    );
    message = 'Als dit account bestaat, ontvang je instructies per e-mail.';
  }

  Future<void> allowAccountChange() async {
    if (widget.account == null && await Runtime.hasOpenActivity()) {
      throw AccountFailure(
        'Bewaar eerst je lopende rit of training voordat je van account wisselt.',
      );
    }
  }

  Future<void> submit() => run(() async {
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.text.trim())) {
      throw AccountFailure('Vul een geldig e-mailadres in.');
    }
    if (password.text.length < 12) {
      throw AccountFailure('Gebruik een wachtwoord van minimaal 12 tekens.');
    }
    await allowAccountChange();
    await account.login(email.text.trim(), password.text, register: register);
    if (mounted) password.clear();
  });

  Future<bool> confirmDelete() async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Account verwijderen?'),
          content: const Text(
            'Je VELO-account, opgeslagen gegevens en koppelingen worden verwijderd. Vul eerst je wachtwoord in.',
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
    appBar: AppBar(
      title: Text(
        widget.onContinueOffline != null ? 'Welkom bij VELO' : 'VELO-account',
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Jouw VELO', style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 12),
        const Text(
          'Bewaar je ritten bij je account en verbind je favoriete apps. Je fietscomputer blijft ook zonder verbinding werken.',
        ),
        if (widget.onContinueOffline != null)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Start je rit met START. Je ritten blijven eerst op dit toestel bewaard en synchroniseren wanneer er verbinding is. Strava vind je later bij Apps.',
            ),
          ),
        if (account.localNetworkOnly)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Deze versie werkt op je thuisnetwerk.'),
          ),
        if (uiBusy) const LinearProgressIndicator(),
        if (message ?? account.message case final String text)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(text, key: const ValueKey('account-message')),
          ),
        if (account.user == null) ...[
          TextField(
            key: const ValueKey('account-email'),
            controller: email,
            decoration: const InputDecoration(labelText: 'E-mailadres'),
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.username, AutofillHints.email],
            autocorrect: false,
          ),
          TextField(
            key: const ValueKey('account-password'),
            controller: password,
            decoration: const InputDecoration(
              labelText: 'Wachtwoord · minimaal 12 tekens',
            ),
            obscureText: true,
            textInputAction: TextInputAction.done,
            autofillHints: [
              register ? AutofillHints.newPassword : AutofillHints.password,
            ],
            onSubmitted: (_) => uiBusy ? null : submit(),
            enableSuggestions: false,
            autocorrect: false,
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const ValueKey('account-submit'),
            onPressed: uiBusy ? null : submit,
            child: Text(register ? 'Account aanmaken' : 'Inloggen'),
          ),
          TextButton(
            onPressed: uiBusy
                ? null
                : () => setState(() => register = !register),
            child: Text(
              register ? 'Ik heb al een account' : 'Nieuw account aanmaken',
            ),
          ),
          TextButton(
            onPressed: uiBusy ? null : () => run(reset),
            child: const Text('Wachtwoord vergeten'),
          ),
          if (widget.onContinueOffline != null)
            TextButton(
              onPressed: uiBusy ? null : widget.onContinueOffline,
              child: const Text('Verder zonder account'),
            ),
        ] else ...[
          Card(
            child: ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(
                account.user?['email'] ?? account.user?['username'] ?? 'VELO',
              ),
              subtitle: const Text('Aangemeld bij VELO'),
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
          if (widget.account == null)
            ListenableBuilder(
              listenable: Runtime.accountSync,
              builder: (context, _) => Card(
                child: ListTile(
                  leading: Icon(
                    Runtime.accountSync.busy
                        ? Icons.sync
                        : Icons.cloud_done_outlined,
                  ),
                  title: const Text(
                    'Je gegevens worden automatisch bijgewerkt',
                  ),
                  subtitle: Text(
                    Runtime.accountSync.message ??
                        (Runtime.accountSync.lastSuccess == null
                            ? 'Nieuwe ritten, routes en instellingen worden bij je account bewaard.'
                            : 'Je wijzigingen zijn gesynchroniseerd.'),
                  ),
                  trailing: IconButton(
                    tooltip: 'Nu synchroniseren',
                    icon: const Icon(Icons.refresh),
                    onPressed: uiBusy
                        ? null
                        : () => run(Runtime.accountSync.run),
                  ),
                ),
              ),
            ),
          if (widget.account == null)
            FutureBuilder(
              future: Runtime.database.documents('account-conflict'),
              builder: (context, snapshot) {
                final rows = (snapshot.data ?? <String, String>{}).entries
                    .where(
                      (row) =>
                          jsonDecode(row.value)['owner'] == account.user?['id'],
                    )
                    .toList();
                if (rows.isEmpty) return const SizedBox.shrink();
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Bewaarde versies'),
                        const Text(
                          'Twee toestellen wijzigden dezelfde gegevens. Beide versies zijn bewaard. Je kunt een eerdere versie terugzetten.',
                        ),
                        for (final row in rows)
                          ListTile(
                            title: Text('${jsonDecode(row.value)['id']}'),
                            subtitle: Text(
                              '${jsonDecode(row.value)['created']}',
                            ),
                            trailing: TextButton(
                              onPressed: uiBusy
                                  ? null
                                  : () => run(
                                      () => Runtime.accountSync.restoreVersion(
                                        row.key,
                                      ),
                                    ),
                              child: const Text('Terugzetten'),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          OutlinedButton(
            onPressed: uiBusy ? null : () => run(account.restore),
            child: const Text('Verbinding opnieuw proberen'),
          ),
          if (!account.passwordRecovery)
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
            onPressed: uiBusy
                ? null
                : () => run(() async {
                    await allowAccountChange();
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
            child: Text(
              account.passwordRecovery
                  ? 'Nieuw wachtwoord opslaan'
                  : 'Wachtwoord wijzigen en sessies intrekken',
            ),
          ),
          OutlinedButton(
            onPressed: uiBusy
                ? null
                : () => run(() async {
                    await allowAccountChange();
                    await Runtime.integrations.strava.cache.expire(all: true);
                    await account.logout();
                  }),
            child: const Text('Uitloggen'),
          ),
          TextButton(
            onPressed: uiBusy
                ? null
                : () => run(() async {
                    await allowAccountChange();
                    if (!await confirmDelete()) return;
                    await account.request(
                      'DELETE',
                      '/api/v1/me',
                      body: {'password': password.text},
                    );
                    if (widget.account == null && account.user?['id'] != null) {
                      await Runtime.accountSync.forgetUser(account.user!['id']);
                    }
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
