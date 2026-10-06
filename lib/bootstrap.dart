import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/di/core_providers.dart';
import 'app/startup/app_services.dart';
import 'app/startup/startup_failure_app.dart';
import 'content/content_pack.dart';
import 'core/logging/app_logger.dart';
import 'features/quest/presentation/journey_providers.dart';
import 'features/settings/data/settings_store.dart';
import 'features/settings/domain/app_settings.dart';
import 'features/settings/presentation/app_settings_controller.dart';
import 'security/secure_key_store.dart';

enum _AppLog implements LogEventCode {
  uncaughtFlutterError,
  uncaughtError,
  startupFailed,
}

/// Ordered start-up: bindings, orientation, error handlers, then the app.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Portrait on phones and tablets. On Android 16+ large screens the system
  // may ignore this request; layouts adapt to any width (DESIGN_SYSTEM.md).
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final store = KeystoreSecureKeyStore();
  // The embedded pack: the journey works offline from the first launch. It
  // is checked at build time (tool/content_build.dart --check and a test
  // that parses the asset), so it is loaded outside the try below: a content
  // defect must never offer to erase the user's local data.
  final pack = ContentPack.parse(await rootBundle.loadString(basePackAsset));

  final AppServices services;
  try {
    services = await AppServices.start(store);
  } on Object catch (error, stack) {
    final logger = AppLogger(sinks: [if (kDebugMode) const DeveloperLogSink()]);
    logger.error(_AppLog.startupFailed, error, stack);
    runApp(
      StartupFailureApp(
        error: error,
        onReset: () async {
          await AppServices.resetLocalData(store);
          await bootstrap();
        },
      ),
    );
    return;
  }

  final settingsStore = SettingsStore(services.database);
  AppSettings settings;
  try {
    settings = await settingsStore.load();
  } on Object {
    settings = const AppSettings(); // display preferences only
  }

  final container = ProviderContainer(
    overrides: [
      secureKeyStoreProvider.overrideWithValue(store),
      appServicesProvider.overrideWithValue(services),
      contentPackProvider.overrideWithValue(pack),
      settingsStoreProvider.overrideWithValue(settingsStore),
      initialSettingsProvider.overrideWithValue(settings),
    ],
  );
  final logger = container.read(appLoggerProvider);

  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    logger.error(
      _AppLog.uncaughtFlutterError,
      details.exception,
      details.stack ?? StackTrace.empty,
    );
    if (kDebugMode) previousOnError?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    logger.error(_AppLog.uncaughtError, error, stack);
    return true;
  };

  runApp(
    UncontrolledProviderScope(container: container, child: const EripooApp()),
  );
}
