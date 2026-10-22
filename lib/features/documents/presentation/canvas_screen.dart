import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../core/format/eripoo_formatter.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../project/presentation/project_screen.dart';
import '../../quest/presentation/journey_providers.dart';
import '../application/canvas.dart';
import '../application/project_synthesis.dart';
import 'documents_providers.dart';

/// One canvas line, in words.
String canvasEntryText(
  AppLocalizations l10n,
  EripooFormatter f,
  CanvasEntry entry,
) => switch (entry) {
  TextEntry(:final text) => text,
  ValidatedEntry(:final statement) => l10n.canvasTested(statement),
  PriceEntry(:final priceMga) => l10n.canvasPrice(f.money(priceMga)),
  VolumeEntry(:final first, :final last) => l10n.canvasVolume(
    f.integer(first),
    f.integer(last),
  ),
  AmountEntry(:final label, :final amountMga) => l10n.canvasAmount(
    label,
    f.money(amountMga),
  ),
};

/// The Business Model Canvas (CLAUDE.md §16): no nine empty boxes; the
/// blocks already built from the work come first, then what is left to
/// build and where to build it.
class CanvasScreen extends ConsumerWidget {
  const CanvasScreen({super.key});

  Future<void> _work(
    BuildContext context,
    WidgetRef ref,
    ProjectSynthesis s,
    CanvasBlockKind kind,
  ) async {
    switch (sourceOf(kind)) {
      case FinanceSource():
        context.go(AppRoutes.finances);
      case SectionSource(:final section):
        final schema = ref.read(contentPackProvider).section(section);
        if (schema == null) return;
        await editProjectSection(
          context,
          ref,
          s.project.id,
          schema,
          s.sections[section] ?? const {},
        );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final f = context.formatter;
    final synthesis = ref.watch(synthesisProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.canvasTitle)),
      body: synthesis.when(
        loading: () => const EripooLoadingView(),
        error: (_, _) => const EripooErrorView(),
        data: (s) {
          if (s == null) {
            return EripooMessageView(
              icon: Icons.work_outline,
              title: l10n.projectEmptyTitle,
              message: l10n.projectEmptyBody,
            );
          }
          final blocks = canvasOf(s);
          final filled = blocks.where((b) => b.filled).toList();
          final empty = blocks.where((b) => !b.filled).toList();
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: EripooSpacing.lg),
            children: [
              ReadableColumn(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l10n.canvasIntro),
                    const SizedBox(height: EripooSpacing.sm),
                    Text(
                      l10n.canvasProgress(
                        f.fraction(filled.length, blocks.length),
                      ),
                      style: context.textStyles.labelLarge,
                    ),
                    for (final b in filled) ...[
                      const SizedBox(height: EripooSpacing.md),
                      EripooCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.canvasBlock(b.kind.name),
                              style: context.textStyles.titleSmall,
                            ),
                            for (final e in b.entries)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: EripooSpacing.xs,
                                ),
                                child: Text(canvasEntryText(l10n, f, e)),
                              ),
                            EripooButton(
                              label: l10n.canvasWorkOn,
                              icon: Icons.edit_outlined,
                              variant: EripooButtonVariant.tertiary,
                              onPressed: () => _work(context, ref, s, b.kind),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (empty.isNotEmpty) ...[
                      const SizedBox(height: EripooSpacing.xl),
                      Text(
                        l10n.canvasToBuild,
                        style: context.textStyles.titleMedium,
                      ),
                      for (final b in empty) ...[
                        const SizedBox(height: EripooSpacing.sm),
                        EripooCard(
                          onTap: () => _work(context, ref, s, b.kind),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      l10n.canvasBlock(b.kind.name),
                                      style: context.textStyles.titleSmall,
                                    ),
                                    Text(
                                      l10n.canvasBlockHint(b.kind.name),
                                      style: context.textStyles.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                        ),
                      ],
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
