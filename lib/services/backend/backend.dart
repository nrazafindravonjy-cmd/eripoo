import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';
import '../../features/auth/data/supabase_auth_repository.dart';
import '../../features/auth/domain/auth_repository.dart';
import '../../security/secure_key_store.dart';
import '../../sync/remote/media_remote.dart';
import '../../sync/remote/supabase_media_remote.dart';
import '../../sync/remote/supabase_sync_remote.dart';
import '../../sync/remote/sync_remote.dart';
import 'secure_session_storage.dart';

/// The server, when the build has one (`--dart-define-from-file`). Without
/// it the app is a complete offline app (guest); this is a normal state.
///
/// Production is refused on purpose: the production project must not
/// exist yet (DEVELOPMENT_PLAN), so a build pointing to one is a mistake.
class Backend {
  Backend._(this.client);

  final SupabaseClient client;

  static Backend? _started;

  /// Starts the client once per isolate. Never waits for the network: a
  /// stored session is restored from the Keystore and refreshed later.
  static Future<Backend?> start(AppConfig config, SecureKeyStore store) async {
    if (!config.hasBackend || config.environment == AppEnvironment.production) {
      return null;
    }
    if (_started case final started?) return started;
    await Supabase.initialize(
      url: config.supabaseUrl,
      // The public client key (anon or publishable): protected by RLS.
      publishableKey: config.supabaseAnonKey,
      authOptions: FlutterAuthClientOptions(
        localStorage: SecureSessionStorage(store),
        pkceAsyncStorage: SecurePkceStorage(store),
      ),
      debug: false,
    );
    return _started = Backend._(Supabase.instance.client);
  }

  AuthRepository get auth => SupabaseAuthRepository(client.auth);
  SyncRemote get sync => SupabaseSyncRemote(client);
  MediaRemote get media => SupabaseMediaRemote(client);

  /// The signed-in account, if any (no network needed).
  String? get userId => client.auth.currentUser?.id;
}
