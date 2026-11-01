import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bike_computer/database/bike_computer_database.dart';
import 'package:bike_computer/services/accounts/account_service.dart';
import 'package:bike_computer/services/accounts/account_sync.dart';

import 'accounts_sync_test.dart' show Tokens;

class SyncServer {
  final documents = <String, Map<String, dynamic>>{};
  int revision = 0, writes = 0;
  bool offline = false, revoked = false;
  Future<void> Function()? beforeData;
  http.Client client() => MockClient((request) async {
    if (offline) throw http.ClientException('offline');
    http.Response reply(int code, dynamic body) =>
        http.Response(jsonEncode(body), code);
    final path = request.url.path;
    if (path.endsWith('/login')) {
      final id = (jsonDecode(request.body)['email'] as String).split('@').first;
      return reply(200, {
        'access_token': id,
        'refresh_token': 'refresh-$id',
        'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 900,
        'user': {'id': id, 'email': '$id@example.test'},
      });
    }
    if (revoked) {
      return reply(401, {
        'error': {'code': 'session_expired', 'message': 'Expired'},
      });
    }
    final owner = request.headers['Authorization']?.replaceFirst('Bearer ', '');
    if (owner == null && !path.endsWith('/logout')) return reply(401, {});
    if (path.endsWith('/logout')) return reply(200, {});
    if (path.endsWith('/me')) {
      return reply(200, {'id': owner, 'email': '$owner@example.test'});
    }
    final parts = request.url.pathSegments;
    if (parts.length < 4 || parts[2] != 'data') return reply(404, {});
    final kind = parts[3];
    if (request.method == 'GET') {
      final hook = beforeData;
      beforeData = null;
      if (hook != null) await hook();
      final after =
          int.tryParse(request.url.queryParameters['after'] ?? '0') ?? 0;
      final rows =
          documents.entries
              .where(
                (entry) =>
                    entry.key.startsWith('$owner|$kind|') &&
                    entry.value['revision'] > after,
              )
              .map((entry) => entry.value)
              .toList()
            ..sort(
              (a, b) => (a['revision'] as int).compareTo(b['revision'] as int),
            );
      return reply(200, {
        'items': rows,
        'cursor': rows.isEmpty ? after : rows.last['revision'],
        'has_more': false,
      });
    }
    final id = parts[4], key = '$owner|$kind|$id';
    final old = documents[key];
    if (request.method == 'PUT') {
      final body = jsonDecode(request.body);
      if (old != null && body['expected_revision'] != old['revision']) {
        return reply(409, {
          'error': {'code': 'revision_conflict', 'message': 'Conflict'},
        });
      }
      writes++;
      documents[key] = {
        'id': id,
        'payload': body['payload'],
        'revision': ++revision,
        'deleted': false,
      };
      return reply(200, {'id': id, 'revision': revision});
    }
    if (request.method == 'DELETE') {
      if (old != null &&
          '${old['revision']}' !=
              request.url.queryParameters['expected_revision']) {
        return reply(409, {
          'error': {'message': 'Conflict'},
        });
      }
      documents[key] = {
        'id': id,
        'payload': null,
        'revision': ++revision,
        'deleted': true,
      };
      return reply(200, {'deleted': true, 'revision': revision});
    }
    return reply(404, {});
  });
}

class Device {
  final db = BikeComputerDatabase(executor: NativeDatabase.memory());
  late final AccountService account;
  late final AccountSync sync;
  Device(SyncServer server) {
    account = AccountService(
      baseUrl: 'https://velo.example.test',
      store: Tokens(),
      client: server.client(),
      onIdentityChange: (id) => sync.switchIdentity(id),
      refreshMutex: db.withAccountRefreshLock,
    );
    sync = AccountSync(db, account);
  }
  Future<void> login([String user = 'alice']) =>
      account.login('$user@example.test', 'test-password-123');
  Future<void> close() async {
    sync.dispose();
    account.dispose();
    await db.close();
  }
}

void main() {
  test('a stale background sync cannot restore the previous account after a foreground switch', () async {
    final server = SyncServer();
    final foreground = Device(server);
    final backgroundAccount = AccountService(
      baseUrl: 'https://velo.example.test',
      store: Tokens(),
      client: server.client(),
    );
    final background = AccountSync(foreground.db, backgroundAccount);
    try {
      await foreground.login();
      await foreground.db.putDocument(
        'settings',
        'app',
        '{"theme":"alice-only"}',
      );
      await foreground.sync.run();
      await backgroundAccount.login('alice@example.test', 'test-password-123');
      server.beforeData = () async {
        await foreground.account.logout();
        await foreground.login('bob');
        await foreground.db.putDocument(
          'settings',
          'app',
          '{"theme":"bob-only"}',
        );
      };
      await background.run();
      expect(
        jsonDecode(
          (await foreground.db.getDocument('settings', 'app'))!,
        )['theme'],
        'bob-only',
      );
      expect(await foreground.db.documents('account-conflict'), isEmpty);
      expect(server.writes, 1);
    } finally {
      background.dispose();
      backgroundAccount.dispose();
      await foreground.close();
    }
  });
  test('a server echo does not replace a newer unsent local edit', () async {
    final server = SyncServer();
    final a = Device(server);
    try {
      await a.login();
      await a.db.putDocument('settings', 'app', '{"theme":"oled"}');
      await a.sync.run();
      await a.db.putDocument('settings', 'app', '{"theme":"light"}');
      await a.sync.run();
      expect(
        server.documents['alice|settings|app']!['payload']['theme'],
        'light',
      );
      expect(await a.db.documents('account-conflict'), isEmpty);
    } finally {
      await a.close();
    }
  });
  test('profiles, imported GPX routes and portable preferences sync without local file paths', () async {
    final server = SyncServer();
    final a = Device(server), b = Device(server);
    try {
      await a.login();
      await b.login();
      await a.db.putDocument(
        'profiles',
        'all',
        '[{"id":"road","name":"Wegfiets"}]',
      );
      await a.db.putDocument(
        'settings',
        'app',
        '{"theme":"oled","offlineMap":"/private/device-only.mbtiles"}',
      );
      await a.db.putDocument(
        'routes',
        'gpx:own',
        '{"name":"Eigen route","points":[[51,4],[51.1,4.1]],"steps":[],"waypoints":[]}',
      );
      await a.db.putDocument(
        'route-source',
        'gpx:own',
        '{"source":"GPX-import"}',
      );
      await a.sync.run();
      await b.sync.run();
      expect(
        jsonDecode((await b.db.getDocument('profiles', 'all'))!).first['id'],
        'road',
      );
      expect(await b.db.getDocument('routes', 'gpx:own'), isNotNull);
      expect(
        server.documents['alice|settings|app']!['payload'].containsKey(
          'offlineMap',
        ),
        isFalse,
      );
      expect(
        jsonDecode((await a.db.getDocument('settings', 'app'))!)['offlineMap'],
        '/private/device-only.mbtiles',
      );
      expect(a.sync.message, isNull);
      expect(b.sync.message, isNull);
    } finally {
      await a.close();
      await b.close();
    }
  });
  test('automatic account data protocol syncs two devices without duplicate writes', () async {
    final server = SyncServer();
    final first = Device(server), second = Device(server);
    try {
      await first.login();
      await second.login();
      await first.db.putDocument('settings', 'app', '{"theme":"oled"}');
      await first.sync.run();
      await second.sync.run();
      expect(
        jsonDecode((await second.db.getDocument('settings', 'app'))!)['theme'],
        'oled',
      );
      final writes = server.writes;
      await first.sync.run();
      await second.sync.run();
      expect(server.writes, writes);
      await first.db.removeDocument('settings', 'app');
      await first.sync.run();
      await second.sync.run();
      expect(await second.db.getDocument('settings', 'app'), isNull);
    } finally {
      await first.close();
      await second.close();
    }
  });

  test(
    'concurrent offline edits preserve both versions and can be restored',
    () async {
      final server = SyncServer();
      final a = Device(server), b = Device(server);
      try {
        await a.login();
        await b.login();
        await a.db.putDocument('settings', 'app', '{"theme":"oled"}');
        await a.sync.run();
        await b.sync.run();
        await a.db.putDocument('settings', 'app', '{"theme":"graphite"}');
        await b.db.putDocument('settings', 'app', '{"theme":"light"}');
        await b.sync.run();
        await a.sync.run();
        expect(
          jsonDecode((await a.db.getDocument('settings', 'app'))!)['theme'],
          'light',
        );
        final versions = await a.db.documents('account-conflict');
        expect(versions, isNotEmpty);
        final version = versions.entries.firstWhere(
          (e) => jsonDecode(e.value)['raw'].contains('graphite'),
        );
        await a.sync.restoreVersion(version.key);
        await a.sync.run();
        expect(
          server.documents['alice|settings|app']!['payload']['theme'],
          'graphite',
        );
      } finally {
        await a.close();
        await b.close();
      }
    },
  );

  test(
    'account switching isolates local data and restores the original account',
    () async {
      final server = SyncServer();
      final a = Device(server);
      try {
        await a.login();
        await a.db.putDocument('settings', 'app', '{"theme":"oled"}');
        await a.sync.run();
        await a.account.logout();
        expect(await a.db.getDocument('settings', 'app'), isNull);
        await a.login('bob');
        await a.sync.run();
        expect(await a.db.getDocument('settings', 'app'), isNull);
        expect(
          server.documents.keys.where((key) => key.startsWith('bob|')),
          isEmpty,
        );
        await a.account.logout();
        await a.login();
        expect(
          jsonDecode((await a.db.getDocument('settings', 'app'))!)['theme'],
          'oled',
        );
      } finally {
        await a.close();
      }
    },
  );

  test(
    'offline data is retained and revoked session does not deadlock sync',
    () async {
      final server = SyncServer();
      final a = Device(server);
      try {
        await a.login();
        await a.db.putDocument('settings', 'app', '{"theme":"oled"}');
        server.offline = true;
        await a.sync.run();
        expect(await a.db.getDocument('settings', 'app'), isNotNull);
        expect(a.sync.message, isNotNull);
        server.offline = false;
        await a.sync.run();
        expect(server.writes, 1);
        server.revoked = true;
        await a.sync.run().timeout(const Duration(seconds: 3));
        expect(a.account.state, AccountState.expired);
        expect(await a.db.getDocument('account-archive', 'alice'), isNotNull);
        expect(await a.db.getDocument('settings', 'app'), isNull);
      } finally {
        await a.close();
      }
    },
  );

  test('SQLite refresh lock serializes overlapping token rotations', () async {
    final db = BikeComputerDatabase(executor: NativeDatabase.memory());
    var inside = 0, maximum = 0;
    Future<void> action() async {
      inside++;
      if (inside > maximum) maximum = inside;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      inside--;
    }

    await Future.wait([
      db.withAccountRefreshLock(action),
      db.withAccountRefreshLock(action),
    ]);
    expect(maximum, 1);
    await db.close();
  });
}
