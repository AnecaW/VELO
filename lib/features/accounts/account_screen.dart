import 'package:flutter/material.dart';

import 'dart:convert';
import 'dart:async';

import '../../widgets/velo_ui.dart';
import 'password_screens.dart';

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
  final name = TextEditingController(),
      email = TextEditingController(),
      password = TextEditingController(),
      nextPassword = TextEditingController();
  bool register = false, busy = false;
  bool get uiBusy => busy || account.state == AccountState.signingIn;
  String? message;
  DateTime? resendAfter;
  Timer? cooldown;
  void startCooldown() {
    resendAfter = DateTime.now().add(const Duration(seconds: 60));
    cooldown?.cancel();
    cooldown = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
      if (DateTime.now().isAfter(resendAfter!)) cooldown?.cancel();
    });
  }

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
    cooldown?.cancel();
    for (final c in [name, email, password, nextPassword]) {
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
    if (register &&
        (name.text.trim().length < 2 || name.text.trim().length > 80)) {
      throw AccountFailure('Vul je naam in (2 tot 80 tekens).');
    }
    await allowAccountChange();
    if (register) {
      await account.registerAccount(
        name.text.trim(),
        email.text.trim(),
        password.text,
      );
    } else {
      await account.login(email.text.trim(), password.text);
    }
    if (account.confirmationEmail != null) startCooldown();
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
      title: Text(widget.onContinueOffline != null ? 'VELO' : 'VELO-account'),
    ),
    body: VeloPageList(
      maxWidth: 520,
      children: [
        Text(
          account.user != null
              ? 'Je account'
              : register
              ? 'Maak je account'
              : 'Welkom bij VELO',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const Text(
          'Bewaar je ritten bij je account en verbind je favoriete apps. Je fietscomputer blijft ook zonder verbinding werken.',
        ),
        if (account.localNetworkOnly)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Deze versie werkt op je thuisnetwerk.'),
          ),
        if (uiBusy) const LinearProgressIndicator(),
        if (message ?? account.message case final String text)
          VeloNotice(text, key: const ValueKey('account-message')),
        if (account.user == null && account.confirmationEmail != null) ...[
          const Icon(Icons.mark_email_read_outlined, size: 40),
          const Text(
            'Bevestig je e-mailadres',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
          Text(
            'We hebben een bevestigingsmail aangevraagd voor ${account.confirmationEmail}. Open de link op dit toestel om verder te gaan.',
          ),
          EmailCodeEntry(account: account, email: account.confirmationEmail!),
          FilledButton(
            onPressed: uiBusy || (resendAfter?.isAfter(DateTime.now()) ?? false)
                ? null
                : () => run(() async {
                    await account.resendVerification(
                      account.confirmationEmail!,
                    );
                    startCooldown();
                    message = 'Een nieuwe bevestigingsmail is aangevraagd.';
                  }),
            child: Text(
              (resendAfter?.isAfter(DateTime.now()) ?? false)
                  ? 'Opnieuw versturen over ${resendAfter!.difference(DateTime.now()).inSeconds + 1} s'
                  : 'Verificatiemail opnieuw versturen',
            ),
          ),
          TextButton(
            onPressed: () => setState(() {
              account.confirmationEmail = null;
              register = false;
              message = null;
            }),
            child: const Text('Terug naar inloggen'),
          ),
          if (widget.onContinueOffline != null)
            TextButton(
              onPressed: widget.onContinueOffline,
              child: const Text('Verder zonder account'),
            ),
        ] else if (account.user == null) ...[
          if (register)
            TextField(
              key: const ValueKey('account-name'),
              controller: name,
              autofillHints: const [AutofillHints.name],
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: 'Naam',
                counterText: '',
              ),
            ),
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
            onPressed: uiBusy
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => ForgotPasswordScreen(
                        account: account,
                        email: email.text.trim(),
                      ),
                    ),
                  ),
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
              subtitle: Text(
                account.user?['name'] as String? ?? 'Aangemeld bij VELO',
              ),
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
          Text('Beveiliging', style: Theme.of(context).textTheme.titleSmall),
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
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Account verwijderen'),
          ),
        ],
      ],
    ),
  );
}
