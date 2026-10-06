import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../l10n/mg_fallback_localizations.dart';

/// Root widget.
///
/// Phase 0 bootstrap only: theme tokens (Phase 1), go_router navigation and
/// the Riverpod ProviderScope (Phase 1/2) are not wired yet. See
/// docs/DEVELOPMENT_PLAN.md.
class EripooApp extends StatelessWidget {
  const EripooApp({super.key, this.locale});

  /// Forced locale (tests, future language setting). Null follows the device.
  final Locale? locale;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...frameworkLocalizationsDelegates,
      ],
      // Unsupported device locales resolve to French, then the first match.
      localeResolutionCallback: (deviceLocale, supported) {
        for (final candidate in supported) {
          if (candidate.languageCode == deviceLocale?.languageCode) {
            return candidate;
          }
        }
        return const Locale('fr');
      },
      themeMode: ThemeMode.system,
      theme: ThemeData(),
      darkTheme: ThemeData(brightness: Brightness.dark),
      home: const _BootstrapPlaceholder(),
    );
  }
}

/// Temporary Phase 0 home: shows only the app identity. It is not a product
/// screen and will be replaced by the router in a later phase.
class _BootstrapPlaceholder extends StatelessWidget {
  const _BootstrapPlaceholder();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.appTitle, style: textTheme.headlineMedium),
            Text(l10n.slogan, style: textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }
}
