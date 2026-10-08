import 'dart:async';

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
import 'features/account/presentation/account_providers.dart';
import 'features/documents/presentation/pdf_export.dart';
import 'features/hypotheses/presentation/research_providers.dart';
import 'features/quest/presentation/journey_providers.dart';
import 'features/settings/data/settings_store.dart';
import 'features/settings/domain/app_settings.dart';
import 'features/settings/presentation/app_settings_controller.dart';
import 'features/trash/application/trash_service.dart';
import 'features/voice/application/voice_notes.dart';
import 'features/voice/presentation/voice_providers.dart';
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

  late final ProviderContainer container;
  // After a recovery or a transfer (new data key) or an erasure: close
  // everything and start again, so the keys are loaded afresh.
  Future<void> restart() async {
    container.dispose();
    await services.database.close().catchError((Object _) {});
    services.keys.dispose();
    await bootstrap();
  }

  container = ProviderContainer(
    overrides: [
      appRestartProvider.overrideWithValue(restart),
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

  // Elements in the trash for more than 30 days are deleted forever; then
  // encrypted files left by an interrupted save (never plain bytes) or
  // deleted forever; then photos still under the data key replaced by a
  // recovery or a transfer.
  final media = container.read(mediaStoreProvider);
  unawaited(
    TrashService(services.database, media: media)
        .purgeExpired()
        .then((_) => media.purgeOrphans())
        .then((_) async {
          if (services.previousDataKey == null) return;
          // Files opened by neither key are left as they are; the previous key
          // is erased only when every readable file uses the new one.
          await media.resealAll();
          await services.keyManager.forgetPreviousDataKey();
        })
        .catchError((Object _) {}),
  );

  // Exported PDFs are in clear: the ones left by a share (ours and the
  // share sheet's copy) are deleted at each start.
  unawaited(
    container
        .read(exportDirProvider.future)
        .then(purgeExports)
        .catchError((Object _) {}),
  );

  // Spoken answers wait in clear only while being encrypted or played:
  // any left by a crash or a closed app are deleted at each start.
  unawaited(
    container
        .read(voiceTempDirProvider.future)
        .then(VoiceNotes.purgeTemp)
        .catchError((Object _) {}),
  );

  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const [
      'Roboto',
    ], await rootBundle.loadString('assets/fonts/Roboto_LICENSE.txt'));
  });

  runApp(
    UncontrolledProviderScope(container: container, child: const EripooApp()),
  );
}
