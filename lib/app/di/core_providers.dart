import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../../security/secure_key_store.dart';
import '../startup/app_services.dart';

/// Kept in memory for future error reports (docs/SECURITY.md §11).
final memoryLogSinkProvider = Provider<MemoryLogSink>((ref) => MemoryLogSink());

final appLoggerProvider = Provider<AppLogger>(
  (ref) => AppLogger(
    sinks: [
      if (kDebugMode) const DeveloperLogSink(),
      ref.watch(memoryLogSinkProvider),
    ],
    minLevel: kReleaseMode ? LogLevel.warning : LogLevel.debug,
  ),
);

/// Keystore-backed secure storage. Overridden in tests.
final secureKeyStoreProvider = Provider<SecureKeyStore>(
  (ref) => KeystoreSecureKeyStore(),
);

/// Keys and encrypted database opened at start-up (overridden in
/// bootstrap; not available in widget tests that do not need them).
final appServicesProvider = Provider<AppServices>(
  (ref) => throw UnimplementedError('Opened by bootstrap()'),
);
