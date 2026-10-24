import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../quest/presentation/journey_providers.dart';

/// Guide bubbles already read, and whether the user turned them off.
class TipsState {
  const TipsState({this.seen = const {}, this.off = false});

  final Set<String> seen;
  final bool off;

  bool shows(String id) => !off && !seen.contains(id);
}

/// Stored on the phone only (local settings), never synced.
class TipsController extends AsyncNotifier<TipsState> {
  static const _seenKey = 'tips.seen';
  static const _offKey = 'tips.off';

  @override
  Future<TipsState> build() async {
    final db = ref.watch(appDatabaseProvider);
    final seen = await db.readValue(_seenKey);
    return TipsState(
      seen: {
        for (final s in (seen ?? '').split(','))
          if (s.isNotEmpty) s,
      },
      off: await db.readValue(_offKey) == 'true',
    );
  }

  Future<void> dismiss(String id) async {
    final current = state.value ?? const TipsState();
    final seen = {...current.seen, id};
    state = AsyncData(TipsState(seen: seen, off: current.off));
    await ref.read(appDatabaseProvider).writeValue(_seenKey, seen.join(','));
  }

  Future<void> stopAll() async {
    final current = state.value ?? const TipsState();
    state = AsyncData(TipsState(seen: current.seen, off: true));
    await ref.read(appDatabaseProvider).writeValue(_offKey, 'true');
  }
}

final tipsProvider = AsyncNotifierProvider<TipsController, TipsState>(
  TipsController.new,
);

/// A one-time guide bubble above a feature the first time it appears:
/// what it is, in one or two sentences. "Got it" hides it for good; tips
/// can all be turned off. Inline (not an overlay), so it never hides
/// anything and screen readers read it in order.
class FeatureTip extends ConsumerWidget {
  const FeatureTip({
    super.key,
    required this.id,
    required this.message,
    required this.child,
  });

  final String id;
  final String message;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tips = ref.watch(tipsProvider).value;
    if (tips == null || !tips.shows(id)) return child;
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final controller = ref.read(tipsProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          liveRegion: true,
          child: Material(
            color: c.surfaceMuted,
            shape: EripooCutBorder(
              radius: EripooRadii.lg,
              cut: 12,
              side: BorderSide(color: c.brand.base),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                EripooSpacing.lg,
                EripooSpacing.md,
                EripooSpacing.sm,
                EripooSpacing.xs,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.lightbulb_outline,
                        size: 20,
                        color: c.brand.base,
                      ),
                      const SizedBox(width: EripooSpacing.sm),
                      Expanded(child: Text(message)),
                    ],
                  ),
                  Wrap(
                    alignment: WrapAlignment.end,
                    children: [
                      TextButton(
                        onPressed: controller.stopAll,
                        child: Text(l10n.tipStopAll),
                      ),
                      TextButton(
                        onPressed: () => controller.dismiss(id),
                        child: Text(l10n.tipGotIt),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: EripooSpacing.sm),
        child,
      ],
    );
  }
}
