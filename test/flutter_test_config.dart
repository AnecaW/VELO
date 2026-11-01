import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:bike_computer/core/runtime.dart';
import 'package:bike_computer/database/bike_computer_database.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  Runtime.configure(BikeComputerDatabase(executor: NativeDatabase.memory()));
  await testMain();
}
