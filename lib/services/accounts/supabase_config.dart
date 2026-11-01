import 'package:supabase_flutter/supabase_flutter.dart';

import '../integrations/strava_service.dart';

/// Public project coordinates, not a service-role key or an administrator secret.
class VeloSupabase {
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://pdooxhljbutbsotbjbrt.supabase.co',
  );
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_7zrEwIR-ojdVQ13lPldhOA_X_hp88Zz',
  );
  static const redirect = 'ultimatebike://auth/callback';
  static Future<SupabaseClient>? _initializing;
  static Future<SupabaseClient> initialize({bool background = false}) =>
      _initializing ??= _initialize(background);
  static Future<SupabaseClient> _initialize(bool background) async {
    await Supabase.initialize(
      url: url,
      publishableKey: publishableKey,
      debug: false,
      authOptions: FlutterAuthClientOptions(
        // Foreground and Workmanager share a DB lease before refreshing.
        autoRefreshToken: false,
        detectSessionInUri: !background,
        pkceAsyncStorage: SecurePkceStorage(SecureTokenStore()),
        localStorage: SecureSupabaseStorage(SecureTokenStore()),
        detectSessionInUriPredicate: (uri) =>
            uri.scheme == 'ultimatebike' &&
            uri.host == 'auth' &&
            uri.path == '/callback',
      ),
    );
    return Supabase.instance.client;
  }
}

class SecureSupabaseStorage extends LocalStorage {
  final TokenStore store;
  SecureSupabaseStorage(this.store);
  static const key = 'velo-supabase-pdooxhljbutbsotbjbrt-session';
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> hasAccessToken() async => await accessToken() != null;
  @override
  Future<String?> accessToken() => store.read(key);
  @override
  Future<void> persistSession(String value) => store.write(key, value);
  @override
  Future<void> removePersistedSession() => store.write(key, null);
}

class SecurePkceStorage extends GotrueAsyncStorage {
  final TokenStore store;
  SecurePkceStorage(this.store);
  @override
  Future<String?> getItem({required String key}) =>
      store.read('velo-pkce-$key');
  @override
  Future<void> setItem({required String key, required String value}) =>
      store.write('velo-pkce-$key', value);
  @override
  Future<void> removeItem({required String key}) =>
      store.write('velo-pkce-$key', null);
}
