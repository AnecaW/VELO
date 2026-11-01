import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/accounts/account_service.dart';
import '../../widgets/velo_ui.dart';

class ForgotPasswordScreen extends StatefulWidget {
  final AccountService account;
  final String email;
  const ForgotPasswordScreen({
    super.key,
    required this.account,
    this.email = '',
  });
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final email = TextEditingController(text: widget.email);
  String? message;
  bool busy = false, sent = false;
  DateTime? resendAfter;
  Timer? cooldown;
  Future<void> send() async {
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.text.trim())) {
      setState(() => message = 'Vul een geldig e-mailadres in.');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await widget.account.request(
        'POST',
        '/api/v1/accounts/password-reset',
        body: {'email': email.text.trim()},
        authenticated: false,
      );
      if (mounted) {
        setState(() {
          sent = true;
          resendAfter = DateTime.now().add(const Duration(seconds: 60));
          cooldown?.cancel();
          cooldown = Timer.periodic(const Duration(seconds: 1), (_) {
            if (mounted) setState(() {});
            if (!DateTime.now().isBefore(resendAfter!)) cooldown?.cancel();
          });
          message = 'Als er een account voor dit adres bestaat, ontvang je een herstelmail. Open de link op dit toestel.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => message = e is AccountFailure
              ? e.message
              : 'De mail kon niet worden aangevraagd. Probeer opnieuw.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Wachtwoord vergeten')),
    body: VeloPageList(
      maxWidth: 480,
      children: [
        const Text(
          'Herstel je toegang',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
        ),
        const Text(
          'We sturen je een link waarmee je een nieuw wachtwoord kunt kiezen.',
        ),
        if (message != null) VeloNotice(message!, error: !sent),
        TextField(
          enabled: !sent,
          key: const ValueKey('reset-email'),
          controller: email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(labelText: 'E-mailadres'),
          onSubmitted: (_) => busy ? null : send(),
        ),
        FilledButton(
          onPressed: busy || (resendAfter?.isAfter(DateTime.now()) ?? false)
              ? null
              : send,
          child: Text(
            busy
                ? 'Aanvragen…'
                : (resendAfter?.isAfter(DateTime.now()) ?? false)
                ? 'Opnieuw aanvragen over ${resendAfter!.difference(DateTime.now()).inSeconds + 1} s'
                : sent
                ? 'Nieuwe herstelmail aanvragen'
                : 'Herstelmail versturen',
          ),
        ),
        if (sent)
          EmailCodeEntry(
            account: widget.account,
            email: email.text.trim(),
            recovery: true,
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Terug naar inloggen'),
        ),
      ],
    ),
  );
  @override
  void dispose() {
    cooldown?.cancel();
    email.dispose();
    super.dispose();
  }
}

class PasswordRecoveryScreen extends StatefulWidget {
  final AccountService account;
  const PasswordRecoveryScreen({super.key, required this.account});
  @override
  State<PasswordRecoveryScreen> createState() => _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<PasswordRecoveryScreen> {
  final password = TextEditingController(), confirm = TextEditingController();
  bool busy = false;
  String? error;
  Future<void> save() async {
    if (password.text.length < 12 || password.text != confirm.text) {
      setState(
        () => error = password.text.length < 12
            ? 'Gebruik minimaal 12 tekens.'
            : 'De wachtwoorden komen niet overeen.',
      );
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.account.completePasswordRecovery(password.text);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is AccountFailure ? e.message : 'Opslaan is niet gelukt. Vraag indien nodig een nieuwe herstelmail aan.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Nieuw wachtwoord')),
    body: VeloPageList(
      maxWidth: 480,
      children: [
        const Text(
          'Kies een nieuw wachtwoord',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
        ),
        const Text(
          'Gebruik minimaal 12 tekens. Daarna meld je je opnieuw aan.',
        ),
        if (error != null) VeloNotice(error!, error: true),
        TextField(
          key: const ValueKey('recovery-password'),
          controller: password,
          obscureText: true,
          autofillHints: const [AutofillHints.newPassword],
          decoration: const InputDecoration(labelText: 'Nieuw wachtwoord'),
        ),
        TextField(
          key: const ValueKey('recovery-confirm'),
          controller: confirm,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Herhaal wachtwoord'),
          onSubmitted: (_) => busy ? null : save(),
        ),
        FilledButton(
          onPressed: busy ? null : save,
          child: Text(busy ? 'Opslaan…' : 'Nieuw wachtwoord opslaan'),
        ),
      ],
    ),
  );
  @override
  void dispose() {
    password.dispose();
    confirm.dispose();
    super.dispose();
  }
}

class InvalidAuthLinkScreen extends StatelessWidget {
  final AccountService account;
  const InvalidAuthLinkScreen({super.key, required this.account});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Link niet beschikbaar')),
    body: VeloPageList(
      maxWidth: 480,
      children: [
        VeloNotice(
          account.authLinkError ?? 'Deze link is verlopen.',
          error: true,
        ),
        FilledButton(
          onPressed: account.dismissAuthLinkError,
          child: const Text('Terug naar VELO'),
        ),
      ],
    ),
  );
}

/// Supabase OTP fallback for reading the mail on another device.
class EmailCodeEntry extends StatefulWidget {
  final AccountService account;
  final String email;
  final bool recovery;
  const EmailCodeEntry({
    super.key,
    required this.account,
    required this.email,
    this.recovery = false,
  });
  @override
  State<EmailCodeEntry> createState() => _EmailCodeEntryState();
}

class _EmailCodeEntryState extends State<EmailCodeEntry> {
  final code = TextEditingController();
  bool busy = false;
  String? error;
  Future<void> verify() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.account.verifyEmailCode(
        widget.email,
        code.text,
        recovery: widget.recovery,
      );
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is AccountFailure
              ? e.message
              : 'Controleren is niet gelukt. Probeer opnieuw.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Lees je de mail op een ander toestel? Vul dan hier de code uit die mail in.',
      ),
      const SizedBox(height: 12),
      if (error != null) VeloNotice(error!, error: true),
      TextField(
        key: const ValueKey('email-code'),
        controller: code,
        keyboardType: TextInputType.number,
        autofillHints: const [AutofillHints.oneTimeCode],
        maxLength: 10,
        decoration: const InputDecoration(
          labelText: 'Code uit de e-mail',
          counterText: '',
        ),
        onSubmitted: (_) => busy ? null : verify(),
      ),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: busy ? null : verify,
        child: Text(busy ? 'Controleren…' : 'Code bevestigen'),
      ),
    ],
  );
  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }
}
