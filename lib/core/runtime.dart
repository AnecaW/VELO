import 'package:bike_computer/services/integrations/strava_integration.dart';
import 'package:bike_computer/services/accounts/account_service.dart';
import 'package:bike_computer/services/accounts/account_sync.dart';
import 'package:bike_computer/models/ride_session.dart';
import 'package:bike_computer/services/ride/session_codec.dart';
import 'package:bike_computer/services/integrations/backend_strava.dart';
import 'package:bike_computer/services/training/training_generator.dart';
import 'package:bike_computer/services/training/workout_runner.dart';
import 'package:bike_computer/services/recording/ride_controller.dart';
import 'package:bike_computer/services/integrations/sync_scheduler.dart';
import 'package:bike_computer/database/bike_computer_database.dart';
import 'package:bike_computer/core/settings.dart';
import 'package:bike_computer/services/bluetooth/ble_sensor_manager.dart';

class Runtime {
  static final AccountService accounts = AccountService(
    refreshMutex: (action) => database.withAccountRefreshLock(action),
    onIdentityChange: (next) async {
      // Expiry must not change the owner of a recording still in progress.
      if (next == null && await hasOpenActivity()) return;
      if (await database.getDocument('account-owner', 'current') == next) {
        return;
      }
      await StravaCache(database).expire(all: true);
      await accountSync.switchIdentity(next);
      _ride?.dispose();
      _ride = null;
      _runner?.dispose();
      _runner = null;
      for (final kind in [
        'sync',
        'sync-history',
        'integration-state',
        'integration-preferences',
      ]) {
        for (final key in (await database.documents(kind)).keys) {
          await database.removeDocument(kind, key);
        }
      }
      for (final key in [
        'strava-state',
        'strava-verifier',
        'strava-auth-started',
        'strava-token',
        'strava-reconnect',
      ]) {
        await accounts.store.write(key, null);
      }
    },
  );
  static var database = BikeComputerDatabase();
  static var settings = AppSettings(database);
  static Future<bool> hasOpenActivity() async {
    if (_runner?.plan != null && _runner?.complete == false) return true;
    final state = _ride?.session.state;
    if (state != null &&
        ![RideState.idle, RideState.ready, RideState.saved].contains(state)) {
      return true;
    }
    final pending = await database.getDocument('active', 'ride');
    return pending != null && SessionCodec.decode(pending).startTime != null;
  }

  static AccountSync? _accountSync;
  static AccountSync get accountSync => _accountSync ??= AccountSync(
    database,
    accounts,
    onSettingsChanged: () => settings.load(),
  );
  static final sensors = BleSensorManager();
  static WorkoutRunner? _runner;
  static WorkoutRunner get workout =>
      _runner ??= WorkoutRunner(TrainingStore(database), sensors);
  static RideController? _ride;
  static RideController get ride =>
      _ride ??= RideController(database, settings, sensors);
  static String? lastError;
  static IntegrationCoordinator? _integrations;
  static IntegrationCoordinator get integrations =>
      _integrations ??= IntegrationCoordinator(
        BackendStravaIntegration(BackendStravaService(database, accounts)),
        syncAccount: () => accountSync.run(),
      );
  static void configure(BikeComputerDatabase db) {
    _accountSync?.dispose();
    _accountSync = null;
    _integrations?.dispose();
    _integrations = null;
    _ride?.dispose();
    _ride = null;
    _runner?.dispose();
    _runner = null;
    database = db;
    settings = AppSettings(db);
  }
}
