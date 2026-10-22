import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../quest/presentation/content_widgets.dart';
import '../../settings/presentation/app_settings_controller.dart';
import '../application/badge_service.dart';
import 'badges_providers.dart';

/// Earned badges first, then how to earn the others. No ranking.
class BadgesScreen extends ConsumerWidget {
  const BadgesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final badges = ref.watch(badgesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.badgesTitle)),
      body: badges.when(
        loading: () => const EripooLoadingView(),
        error: (_, _) => const EripooErrorView(),
        data: (badges) {
          final earned = badges.where((b) => b.earned).toList();
          final toEarn = badges.where((b) => !b.earned).toList();
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: EripooSpacing.lg),
            children: [
              ReadableColumn(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l10n.badgesIntro),
                    const SizedBox(height: EripooSpacing.lg),
                    Text(
                      l10n.badgesEarned,
                      style: context.textStyles.titleMedium,
                    ),
                    const SizedBox(height: EripooSpacing.sm),
                    if (earned.isEmpty) Text(l10n.badgesNone),
                    for (final b in earned) _BadgeCard(state: b),
                    const SizedBox(height: EripooSpacing.lg),
                    if (toEarn.isNotEmpty) ...[
                      Text(
                        l10n.badgesToEarn,
                        style: context.textStyles.titleMedium,
                      ),
                      const SizedBox(height: EripooSpacing.sm),
                      for (final b in toEarn) _BadgeCard(state: b),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BadgeCard extends StatelessWidget {
  const _BadgeCard({required this.state});

  final BadgeState state;

  @override
  Widget build(BuildContext context) {
    final badge = state.badge;
    final title = contentText(context, badge.title);
    return Padding(
      padding: const EdgeInsets.only(bottom: EripooSpacing.sm),
      child: EripooCard(
        semanticLabel: title,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              state.earned ? Icons.military_tech : Icons.lock_outline,
              color: state.earned ? null : context.colors.textSecondary,
            ),
            const SizedBox(width: EripooSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.textStyles.titleSmall),
                  const SizedBox(height: EripooSpacing.xs),
                  Text(
                    contentText(
                      context,
                      state.earned ? badge.description : badge.hint,
                    ),
                    style: context.textStyles.bodyMedium,
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

/// Announces new badges once on Home (if celebrations are on), then marks
/// them seen on every device. Shows nothing itself.
class BadgeCelebration extends ConsumerStatefulWidget {
  const BadgeCelebration({super.key});

  @override
  ConsumerState<BadgeCelebration> createState() => _BadgeCelebrationState();
}

class _BadgeCelebrationState extends ConsumerState<BadgeCelebration> {
  bool _announcing = false;

  Future<void> _announce(List<BadgeState> fresh) async {
    if (_announcing) return;
    _announcing = true;
    final service = ref.read(badgeServiceProvider);
    final ids = fresh.map((b) => b.badge.id).toList();
    if (ref.read(appSettingsProvider).celebrations) {
      final l10n = AppLocalizations.of(context);
      final names = fresh
          .map((b) => contentText(context, b.badge.title))
          .join(', ');
      final open = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.military_tech),
          title: Text(l10n.badgesCelebrationTitle(fresh.length)),
          content: Text(l10n.badgesCelebrationBody(names)),
          actions: [
            EripooButton(
              label: l10n.actionClose,
              variant: EripooButtonVariant.tertiary,
              onPressed: () => Navigator.of(context).pop(false),
            ),
            EripooButton(
              label: l10n.badgesSee,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      );
      await service.markSeen(ids);
      if (open == true && mounted) context.go(AppRoutes.badges);
    } else {
      await service.markSeen(ids);
    }
    _announcing = false;
  }

  @override
  Widget build(BuildContext context) {
    final fresh = (ref.watch(badgesProvider).value ?? const <BadgeState>[])
        .where((b) => b.isNew)
        .toList();
    if (fresh.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _announce(fresh);
      });
    }
    return const SizedBox.shrink();
  }
}
