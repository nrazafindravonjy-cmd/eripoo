import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_system/design_system.dart';
import '../features/settings/domain/app_settings.dart';
import '../features/settings/presentation/app_settings_controller.dart';
import '../l10n/generated/app_localizations.dart';
import '../l10n/mg_fallback_localizations.dart';
import 'router/app_router.dart';

/// Root widget: theme (light/dark), languages, reduced motion and router.
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
      // Until the onboarding language choice exists (Phase 2), an
      // unsupported device language falls back to French.
      localeResolutionCallback: (deviceLocale, supported) {
        for (final candidate in supported) {
          if (candidate.languageCode == deviceLocale?.languageCode) {
            return candidate;
          }
        }
        return const Locale('fr');
      },
      themeMode: switch (settings.theme) {
        ThemePreference.system => ThemeMode.system,
        ThemePreference.light => ThemeMode.light,
        ThemePreference.dark => ThemeMode.dark,
      },
      theme: EripooTheme.light(),
      darkTheme: EripooTheme.dark(),
      // The Eripoo "reduce animations" setting is applied through
      // MediaQuery so that every widget has a single source of truth.
      builder: (context, child) {
        if (!settings.reducedMotion) return child!;
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        );
      },
    );
  }
}
