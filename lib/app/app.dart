import 'package:flutter/material.dart';
import 'package:bike_computer/core/runtime.dart';
import 'package:bike_computer/app/router.dart';
import 'package:bike_computer/app/theme.dart';
import 'package:bike_computer/features/accounts/account_gate.dart';

class BikeComputerApp extends StatelessWidget {
  final bool showAccountWelcome;
  const BikeComputerApp({super.key, this.showAccountWelcome = false});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Runtime.settings,
      builder: (context, _) => MaterialApp.router(
        title: 'Velo · Bike Computer',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(
          light: true,
          oled: false,
          accent: Color(Runtime.settings.value('accent', 0xff36bfa1)),
          contrast: Runtime.settings.value('contrast', false),
        ),
        darkTheme: AppTheme.build(
          light: false,
          oled: Runtime.settings.value('theme', 'oled') != 'graphite',
          accent: Color(Runtime.settings.value('accent', 0xff7cdec2)),
          contrast: Runtime.settings.value('contrast', false),
        ),
        themeMode: switch (Runtime.settings.value('theme', 'oled')) {
          'light' => ThemeMode.light,
          'system' => ThemeMode.system,
          _ => ThemeMode.dark,
        },
        routerConfig: router,
        builder: (context, child) => showAccountWelcome
            ? AccountGate(account: Runtime.accounts, child: child!)
            : child!,
      ),
    );
  }
}
