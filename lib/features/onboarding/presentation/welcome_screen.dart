import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_language.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../settings/presentation/app_settings_controller.dart';

/// First screens: choose the language (the phone's preselected), then a
/// three-screen introduction (skippable), then Home. No account, no
/// network: the diagnostic follows on the home screen. Nothing is saved
/// before "Start", so the introduction shows in the language chosen.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  late AppLanguage _language =
      AppLanguage.tryParse(
        WidgetsBinding.instance.platformDispatcher.locale.languageCode,
      ) ??
      AppLanguage.fr;

  /// Anonymous statistics: off unless ticked (decision D7).
  bool _usageStats = false;

  /// 0: language; 1 to [_introPages]: introduction.
  int _page = 0;
  static const _introPages = 3;

  void _start() {
    final settings = ref.read(appSettingsProvider.notifier);
    if (_usageStats) settings.setUsageStats(true);
    settings.setLanguage(_language);
  }

  @override
  Widget build(BuildContext context) {
    // The screen is shown in the language being chosen.
    return Localizations.override(
      context: context,
      locale: Locale(_language.name),
      child: PopScope(
        // System back goes to the previous introduction screen.
        canPop: _page == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) setState(() => _page--);
        },
        child: Builder(
          builder: (context) =>
              _page == 0 ? _build(context) : _buildIntro(context),
        ),
      ),
    );
  }

  Widget _buildIntro(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final (title, body) = switch (_page) {
      1 => (l10n.onboarding1Title, l10n.onboarding1Body),
      2 => (l10n.onboarding2Title, l10n.onboarding2Body),
      _ => (l10n.onboarding3Title, l10n.onboarding3Body),
    };
    final last = _page == _introPages;
    final motion = EripooMotion.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => setState(() => _page--)),
        actions: [
          if (!last)
            TextButton(onPressed: _start, child: Text(l10n.onboardingSkip)),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: motion.normal,
                child: ListView(
                  key: ValueKey(_page),
                  padding: const EdgeInsets.symmetric(
                    vertical: EripooSpacing.xl,
                  ),
                  children: [
                    ReadableColumn(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: EripooOrganicShape(
                              size: 200,
                              seed: _page * 5 + 2,
                            ),
                          ),
                          const SizedBox(height: EripooSpacing.xxl),
                          EripooHeadline(
                            title,
                            style: context.textStyles.displaySmall,
                          ),
                          const SizedBox(height: EripooSpacing.md),
                          Text(body, style: context.textStyles.bodyLarge),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Where the user is in the introduction.
            Semantics(
              label: l10n.onboardingPage(_page, _introPages),
              excludeSemantics: true,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 1; i <= _introPages; i++)
                    AnimatedContainer(
                      duration: motion.fast,
                      margin: const EdgeInsets.symmetric(
                        horizontal: EripooSpacing.xxs,
                      ),
                      width: i == _page ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _page ? c.brand.base : c.border,
                        borderRadius: BorderRadius.circular(EripooRadii.pill),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: EripooSpacing.md),
              child: ReadableColumn(
                child: EripooSwipeAction(
                  label: last ? l10n.welcomeStart : l10n.onboardingNext,
                  onAction: last ? _start : () => setState(() => _page++),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    String name(AppLanguage language) => switch (language) {
      AppLanguage.fr => l10n.languageFr,
      AppLanguage.en => l10n.languageEn,
    };
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  vertical: EripooSpacing.xxl,
                ),
                children: [
                  ReadableColumn(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            EripooLogo(size: 56, semanticLabel: l10n.appTitle),
                            const Spacer(),
                            const EripooOrganicShape(size: 120, seed: 3),
                          ],
                        ),
                        const SizedBox(height: EripooSpacing.xl),
                        EripooHeadline(
                          l10n.welcomeTitle,
                          style: context.textStyles.displaySmall,
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
                            if (value != null) {
                              setState(() => _language = value);
                            }
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
                        const SizedBox(height: EripooSpacing.md),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: _usageStats,
                          title: Text(l10n.welcomeUsageStats),
                          onChanged: (v) =>
                              setState(() => _usageStats = v ?? false),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Always visible, within reach of the thumb.
            Padding(
              padding: const EdgeInsets.symmetric(vertical: EripooSpacing.md),
              child: ReadableColumn(
                child: EripooSwipeAction(
                  label: l10n.welcomeContinue,
                  onAction: () => setState(() => _page = 1),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
