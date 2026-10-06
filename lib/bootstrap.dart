import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/di/core_providers.dart';
import 'core/logging/app_logger.dart';

enum _AppLog implements LogEventCode { uncaughtFlutterError, uncaughtError }

/// Ordered start-up: bindings, orientation, error handlers, then the app.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Portrait on phones and tablets. On Android 16+ large screens the system
  // may ignore this request; layouts adapt to any width (DESIGN_SYSTEM.md).
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final container = ProviderContainer();
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
