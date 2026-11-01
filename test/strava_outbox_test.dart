import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bike_computer/database/bike_computer_database.dart';
import 'package:bike_computer/services/accounts/account_service.dart';
import 'package:bike_computer/services/integrations/backend_strava.dart';
import 'package:bike_computer/services/integrations/integration_models.dart';

import 'accounts_sync_test.dart' show Tokens;

class OutboxAccounts extends AccountService {
  bool online = false;
  int uploads = 0;
  OutboxAccounts() : super(store: Tokens()) {
    user = {'id': 'alice'};
  }
  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    bool authenticated = true,
  }) async {
    if (!online) throw AccountFailure('Test network unavailable');
    if (path == '/api/v1/integrations/strava') return {'connected': true};
    if (path.contains('/uploads/')) {
      uploads++;
      return {'job_id': 'test-job'};
    }
    return {'revision': 1};
  }
}

void main() {
  test('offline after-ride uploads survive network failure, remain owner-bound and retry once', () async {
    final db = BikeComputerDatabase(executor: NativeDatabase.memory());
    final accounts = OutboxAccounts();
    final service = BackendStravaService(db, accounts);
    await SyncRepository(db).savePreferences(
      'strava',
      const SyncPreferences(uploads: true, afterRide: true),
    );
    await db.putDocument(
      'ride',
      'test-ride',
      '{"v":1,"id":"test-ride","points":[]}',
    );
    await service.queueAfterRide('test-ride');
    await service.flushOutbox();
    expect((await db.documents('strava-upload-outbox')).length, 1);
    accounts.online = true;
    accounts.user = {'id': 'bob'};
    await service.flushOutbox();
    expect(accounts.uploads, 0);
    accounts.user = {'id': 'alice'};
    await service.flushOutbox();
    expect(accounts.uploads, 1);
    expect(await db.documents('strava-upload-outbox'), isEmpty);
    await service.flushOutbox();
    expect(accounts.uploads, 1);
    service.dispose();
    accounts.dispose();
    await db.close();
  });
}
