import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_system/design_system.dart';
import '../features/app_lock/presentation/app_lock_gate.dart';
import '../features/legal/presentation/legal_screens.dart';
import '../features/settings/presentation/app_settings_controller.dart';
import '../l10n/framework_localizations.dart';
import '../l10n/generated/app_localizations.dart';
import 'router/app_router.dart';

/// Root widget: theme, languages, reduced motion and router.
class EripooApp extends ConsumerWidget {
  const EripooApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final language = settings.language;

    return MaterialApp.router(
      routerConfig: ref.watch(routerProvider),
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      locale: language == null ? null : Locale(language.name),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...frameworkLocalizationsDelegates,
      ],
      // Before the welcome screen's choice (which is shown in the language
      // being chosen), an unsupported device language falls back to French.
      localeResolutionCallback: (deviceLocale, supported) {
        for (final candidate in supported) {
          if (candidate.languageCode == deviceLocale?.languageCode) {
            return candidate;
          }
        }
        return const Locale('fr');
      },
      // Dark only (owner's decision, 2026-10-23).
      themeMode: ThemeMode.dark,
      theme: EripooTheme.dark(),
      darkTheme: EripooTheme.dark(),
      // The Eripoo "reduce animations" setting is applied through
      // MediaQuery so that every widget has a single source of truth.
      builder: (context, child) {
        final gated = EripooGrain(
          child: AppLockGate(child: LegalGate(child: child!)),
        );
        if (!settings.reducedMotion) return gated;
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: gated,
        );
      },
    );
  }
}
