import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/di/core_providers.dart';
import 'app/startup/app_services.dart';
import 'app/startup/startup_failure_app.dart';
import 'core/logging/app_logger.dart';
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

  final container = ProviderContainer(
    overrides: [
      secureKeyStoreProvider.overrideWithValue(store),
      appServicesProvider.overrideWithValue(services),
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
