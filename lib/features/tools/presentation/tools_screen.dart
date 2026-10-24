import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../content/content_pack.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../hypotheses/presentation/research_forms.dart';
import '../../quest/presentation/content_widgets.dart';
import '../../settings/presentation/app_settings_controller.dart';
import '../../tips/presentation/feature_tip.dart';
import '../application/tool_service.dart';
import 'tools_providers.dart';

/// Where a usable tool opens.
String toolRoute(ToolKind kind) => switch (kind) {
  ToolKind.observationJournal => AppRoutes.fieldNotes,
  ToolKind.hypotheses || ToolKind.experiments => AppRoutes.hypotheses,
  ToolKind.interviewGuide => AppRoutes.interviewGuide,
  ToolKind.competitorAnalysis => AppRoutes.competitors,
  ToolKind.priceCalculator => AppRoutes.priceCalculator,
  ToolKind.marginCalculator => AppRoutes.marginCalculator,
  ToolKind.breakEvenCalculator => AppRoutes.breakEvenCalculator,
  ToolKind.businessModelCanvas => AppRoutes.canvas,
  ToolKind.marketingPlan => AppRoutes.marketingPlan,
  ToolKind.businessPlan => AppRoutes.businessPlan,
  ToolKind.pitch => AppRoutes.pitch,
  ToolKind.pitchDeck => AppRoutes.pitchDeck,
  ToolKind.adminPreparation => AppRoutes.adminPreparation,
};

/// The Tools tab (CLAUDE.md §20): tools appear as the user acts; locked
/// ones say how to unlock them and their help is always readable; tools
/// not built yet are announced as such, never imitated.
class ToolsScreen extends ConsumerStatefulWidget {
  const ToolsScreen({super.key});

  @override
  ConsumerState<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends ConsumerState<ToolsScreen> {
  bool _announcing = false;

  /// Shows the new unlocks once (if celebrations are on), then marks them
  /// seen on every device.
  Future<void> _announce(List<ToolState> fresh) async {
    if (_announcing) return;
    _announcing = true;
    final l10n = AppLocalizations.of(context);
    if (ref.read(appSettingsProvider).celebrations) {
      final names = fresh
          .map((t) => contentText(context, t.tool.title))
          .join(', ');
      final open = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.auto_awesome),
          title: Text(l10n.toolsCelebrationTitle(fresh.length)),
          content: Text(l10n.toolsCelebrationBody(names)),
          actions: [
            EripooButton(
              label: l10n.toolsLater,
              variant: EripooButtonVariant.tertiary,
              onPressed: () => Navigator.of(context).pop(false),
            ),
            EripooButton(
              label: l10n.toolsOpen,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      );
      await ref.read(toolServiceProvider).markSeen(fresh.map((t) => t.tool.id));
      if (open == true && mounted) context.go(toolRoute(fresh.first.tool.kind));
    } else {
      await ref.read(toolServiceProvider).markSeen(fresh.map((t) => t.tool.id));
    }
    _announcing = false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tools = ref.watch(toolsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navTools)),
      body: tools.when(
        loading: () => const EripooLoadingView(),
        error: (_, _) => const EripooErrorView(),
        data: (tools) {
          final fresh = tools.where((t) => t.isNew).toList();
          if (fresh.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _announce(fresh);
            });
          }
          final usable = tools.where((t) => t.usable).toList();
          final locked = tools
              .where((t) => !t.unlocked && t.tool.implemented)
              .toList();
          final planned = tools.where((t) => !t.tool.implemented).toList();
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: EripooSpacing.lg),
            children: [
              ReadableColumn(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l10n.toolsIntro),
                    if (usable.isNotEmpty)
                      ..._grid(context, l10n.toolsUnlockedTitle, usable),
                    if (locked.isNotEmpty)
                      ..._section(context, l10n.toolsLockedTitle, locked),
                    if (planned.isNotEmpty)
                      ..._section(context, l10n.toolsPlannedTitle, planned),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Usable tools: the most relevant one (a new one first) takes the full
  /// width, the others share rows of two (hierarchy at a glance).
  List<Widget> _grid(
    BuildContext context,
    String title,
    List<ToolState> tools,
  ) {
    final ordered = [
      ...tools.where((t) => t.isNew),
      ...tools.where((t) => !t.isNew),
    ];
    final rest = ordered.skip(1).toList();
    return [
      const SizedBox(height: EripooSpacing.xl),
      Text(title, style: context.textStyles.titleMedium),
      const SizedBox(height: EripooSpacing.sm),
      FeatureTip(
        id: 'tools.new',
        message: AppLocalizations.of(context).tipToolsNew,
        child: _ToolCard(ordered.first, featured: true),
      ),
      for (var i = 0; i < rest.length; i += 2) ...[
        const SizedBox(height: EripooSpacing.sm),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _ToolCard(rest[i], compact: true)),
              const SizedBox(width: EripooSpacing.sm),
              Expanded(
                child: i + 1 < rest.length
                    ? _ToolCard(rest[i + 1], compact: true)
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ],
    ];
  }

  List<Widget> _section(
    BuildContext context,
    String title,
    List<ToolState> tools,
  ) => [
    const SizedBox(height: EripooSpacing.xl),
    Text(title, style: context.textStyles.titleMedium),
    for (final t in tools) ...[
      const SizedBox(height: EripooSpacing.sm),
      _ToolCard(t),
    ],
  ];
}

class _ToolCard extends StatelessWidget {
  const _ToolCard(this.state, {this.featured = false, this.compact = false});
  final ToolState state;

  /// The full-width tile of the grid: larger title.
  final bool featured;

  /// A half-width tile: icon above the text.
  final bool compact;

  Future<void> _help(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tool = state.tool;
    return showFormSheet<void>(
      context,
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            contentText(context, tool.title),
            style: context.textStyles.titleLarge,
          ),
          const SizedBox(height: EripooSpacing.sm),
          Text(contentText(context, tool.summary)),
          const SizedBox(height: EripooSpacing.md),
          Text(l10n.toolsHelp, style: context.textStyles.labelLarge),
          for (final h in tool.help) ...[
            const SizedBox(height: EripooSpacing.xs),
            Text(contentText(context, h)),
          ],
          if (!state.unlocked && tool.unlockHint != null) ...[
            const SizedBox(height: EripooSpacing.md),
            Text(
              contentText(context, tool.unlockHint!),
              style: context.textStyles.labelLarge,
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tool = state.tool;
    final String? note = state.usable
        ? null
        : !tool.implemented
        ? (state.unlocked ? l10n.toolsPlannedUnlocked : l10n.toolsPlannedNote)
        : tool.unlockHint == null
        ? null
        : contentText(context, tool.unlockHint!);
    if (compact) {
      return EripooCard(
        semanticLabel: contentText(context, tool.title),
        onTap: () => context.go(toolRoute(tool.kind)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.handyman_outlined, color: context.colors.textSecondary),
            const SizedBox(height: EripooSpacing.sm),
            Text(
              contentText(context, tool.title),
              style: context.textStyles.titleSmall,
            ),
            const SizedBox(height: EripooSpacing.xxs),
            Text(
              contentText(context, tool.summary),
              style: context.textStyles.bodySmall,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
    }
    return EripooCard(
      onTap: state.usable
          ? () => context.go(toolRoute(tool.kind))
          : () => _help(context),
      child: Row(
        children: [
          Icon(
            state.usable ? Icons.handyman_outlined : Icons.lock_outline,
            color: state.usable ? null : context.colors.textSecondary,
          ),
          const SizedBox(width: EripooSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        contentText(context, tool.title),
                        style: featured
                            ? context.textStyles.titleLarge
                            : context.textStyles.titleSmall,
                      ),
                    ),
                    if (state.isNew) ...[
                      const SizedBox(width: EripooSpacing.sm),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: context.colors.accent.container,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: EripooSpacing.sm,
                          ),
                          child: Text(
                            l10n.toolsNew,
                            style: context.textStyles.labelSmall?.copyWith(
                              color: context.colors.accent.onContainer,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  contentText(context, tool.summary),
                  style: context.textStyles.bodySmall,
                ),
                if (note != null)
                  Text(note, style: context.textStyles.labelMedium),
              ],
            ),
          ),
          if (state.usable)
            const Icon(Icons.chevron_right)
          else
            IconButton(
              icon: const Icon(Icons.help_outline),
              tooltip: l10n.toolsHelp,
              onPressed: () => _help(context),
            ),
        ],
      ),
    );
  }
}
