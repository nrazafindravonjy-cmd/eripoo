/// Build-time configuration, injected with
/// `--dart-define-from-file=env/<environment>.json` (files not versioned,
/// except `env/example.json` with fake values).
///
/// Only public values belong here: the Supabase URL and its **anon** key
/// (public by design, protected by RLS). Never a service_role key or any
/// other secret (docs/SECURITY.md §17).
enum AppEnvironment { local, development, production }

class AppConfig {
  const AppConfig({
    required this.environment,
    required this.supabaseUrl,
    required this.supabaseAnonKey,
  });

  factory AppConfig.fromEnvironment() => AppConfig(
    environment: switch (const String.fromEnvironment('ERIPOO_ENV')) {
      'production' => AppEnvironment.production,
      'development' => AppEnvironment.development,
      _ => AppEnvironment.local,
    },
    supabaseUrl: const String.fromEnvironment('SUPABASE_URL'),
    supabaseAnonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
  );

  final AppEnvironment environment;
  final String supabaseUrl;
  final String supabaseAnonKey;

  /// Without a backend, the app runs fully offline as a guest (accounts
  /// and synchronisation unavailable). This is a normal state, not an
  /// error. Outside the local environment the server must be reached over
  /// HTTPS: a plain-HTTP address is treated as no backend at all (release
  /// builds also refuse clear text at the Android level).
  bool get hasBackend =>
      supabaseUrl.isNotEmpty &&
      supabaseAnonKey.isNotEmpty &&
      (environment == AppEnvironment.local ||
          supabaseUrl.startsWith('https://'));
}
