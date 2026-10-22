import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../content/content_pack.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../quest/presentation/content_widgets.dart';
import '../../quest/presentation/journey_providers.dart';
import '../../settings/presentation/app_settings_controller.dart';
import '../application/legal_acceptance.dart';

final legalAcceptanceProvider = Provider<LegalAcceptance>(
  (ref) => LegalAcceptance(ref.watch(appDatabaseProvider)),
);

/// True while the current legal texts still have to be accepted.
final legalAcceptanceNeededProvider = FutureProvider<bool>(
  (ref) => ref
      .watch(legalAcceptanceProvider)
      .needed(ref.watch(contentPackProvider).legal),
);

/// The documents, one after the other; a banner while they are
/// placeholders.
class _LegalTexts extends StatelessWidget {
  const _LegalTexts({required this.legal});

  final LegalContent legal;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!legal.validated) ...[
          EripooCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.hourglass_empty),
                const SizedBox(width: EripooSpacing.md),
                Expanded(child: Text(l10n.legalPending)),
              ],
            ),
          ),
          const SizedBox(height: EripooSpacing.lg),
        ],
        for (final d in legal.documents) ...[
          Text(
            contentText(context, d.title),
            style: context.textStyles.titleMedium,
          ),
          const SizedBox(height: EripooSpacing.sm),
          for (final p in d.body) ...[
            Text(contentText(context, p)),
            const SizedBox(height: EripooSpacing.sm),
          ],
          const SizedBox(height: EripooSpacing.md),
        ],
        Text(
          l10n.legalVersion(legal.version),
          style: context.textStyles.bodySmall,
        ),
      ],
    );
  }
}

/// From Profile: read the texts at any time.
class LegalScreen extends ConsumerWidget {
  const LegalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final legal = ref.watch(contentPackProvider).legal;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.legalTitle)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: EripooSpacing.lg),
        children: [
          ReadableColumn(
            child: legal == null
                ? Text(l10n.legalPending)
                : _LegalTexts(legal: legal),
          ),
        ],
      ),
    );
  }
}

/// Covers the app until the current validated texts are accepted (after
/// the language is chosen). Never shown for placeholders.
class LegalGate extends ConsumerWidget {
  const LegalGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final languageChosen = ref.watch(
      appSettingsProvider.select((s) => s.language != null),
    );
    final needed = ref.watch(legalAcceptanceNeededProvider).value ?? false;
    if (!languageChosen || !needed) return child;
    final legal = ref.watch(contentPackProvider).legal!;
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.legalAcceptTitle)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: EripooSpacing.lg),
        children: [
          ReadableColumn(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.legalAcceptIntro),
                const SizedBox(height: EripooSpacing.lg),
                _LegalTexts(legal: legal),
                const SizedBox(height: EripooSpacing.lg),
                EripooButton(
                  label: l10n.legalAccept,
                  expand: true,
                  onPressed: () async {
                    await ref.read(legalAcceptanceProvider).accept(legal);
                    ref.invalidate(legalAcceptanceNeededProvider);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
