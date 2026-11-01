import 'package:flutter/material.dart';

import '../../services/accounts/account_service.dart';
import 'account_screen.dart';

/// Account onboarding never prevents local recording when connectivity is lost.
class AccountGate extends StatefulWidget {
  final AccountService account;
  final Widget child;
  const AccountGate({super.key, required this.account, required this.child});
  @override
  State<AccountGate> createState() => _AccountGateState();
}

class _AccountGateState extends State<AccountGate> {
  bool offline = false;
  bool admitted = false;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.account,
    builder: (context, _) {
      if (!widget.account.initialized) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (widget.account.user != null) {
        admitted = true;
        offline = false;
      }
      if (widget.account.user != null ||
          offline ||
          (admitted && widget.account.state == AccountState.expired)) {
        return widget.child;
      }
      return AccountScreen(
        account: widget.account,
        onContinueOffline: () => setState(() => offline = true),
      );
    },
  );
}
