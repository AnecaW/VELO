import 'package:flutter/material.dart';

import 'dart:async';

import 'package:bike_computer/app/app.dart';
import 'package:bike_computer/core/runtime.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Runtime.settings.load();
  } catch (e) {
    Runtime.lastError = 'Instellingen: $e';
  }
  runApp(const BikeComputerApp());
  unawaited(Runtime.accounts.restore().catchError((Object _) {}));
  unawaited(
    Runtime.integrations.initialize().catchError((Object e) {
      Runtime.lastError = 'Accountsynchronisatie kon niet starten.';
    }),
  );
}
