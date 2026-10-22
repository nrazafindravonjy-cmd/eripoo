import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_language.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../settings/presentation/app_settings_controller.dart';

/// First screen: choose the language (Malagasy preselected), then start.
/// No account, no network: the diagnostic follows on the home screen.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  AppLanguage _language = AppLanguage.mg;

  @override
  Widget build(BuildContext context) {
    // The screen is shown in the language being chosen.
    return Localizations.override(
      context: context,
      locale: Locale(_language.name),
      child: Builder(builder: _build),
    );
  }

  Widget _build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    String name(AppLanguage language) => switch (language) {
      AppLanguage.mg => l10n.languageMg,
      AppLanguage.fr => l10n.languageFr,
      AppLanguage.en => l10n.languageEn,
    };
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: EripooSpacing.xxl),
          children: [
            ReadableColumn(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.welcomeTitle,
                    style: context.textStyles.headlineMedium,
                  ),
                  const SizedBox(height: EripooSpacing.xs),
                  Text(l10n.slogan, style: context.textStyles.bodyLarge),
                  const SizedBox(height: EripooSpacing.xl),
                  Text(
                    l10n.welcomeChooseLanguage,
                    style: context.textStyles.titleMedium,
                  ),
                  const SizedBox(height: EripooSpacing.sm),
                  RadioGroup<AppLanguage>(
                    groupValue: _language,
                    onChanged: (value) {
                      if (value != null) setState(() => _language = value);
                    },
                    child: Column(
                      children: [
                        for (final language in AppLanguage.values)
                          RadioListTile<AppLanguage>(
                            value: language,
                            title: Text(name(language)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: EripooSpacing.lg),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.lock_outline,
                        color: context.colors.brand.base,
                      ),
                      const SizedBox(width: EripooSpacing.sm),
                      Expanded(child: Text(l10n.welcomePrivacy)),
                    ],
                  ),
                  const SizedBox(height: EripooSpacing.xl),
                  EripooButton(
                    label: l10n.welcomeStart,
                    expand: true,
                    onPressed: () => ref
                        .read(appSettingsProvider.notifier)
                        .setLanguage(_language),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
