import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../content/content_pack.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../project/presentation/project_screen.dart';
import '../../quest/presentation/content_widgets.dart';
import '../../quest/presentation/journey_providers.dart';
import '../application/project_synthesis.dart';
import 'document_model.dart';
import 'documents_providers.dart';
import 'pdf_export.dart';

/// Builds documents for the screen's language.
DocumentBuilder documentBuilder(
  BuildContext context,
  WidgetRef ref,
  ProjectSynthesis s,
) => DocumentBuilder(
  synthesis: s,
  l10n: AppLocalizations.of(context),
  formatter: context.formatter,
  pack: ref.read(contentPackProvider),
  text: (t) => contentText(context, t),
);

ToolDefinition? _tool(WidgetRef ref, ToolKind kind) => ref
    .watch(contentPackProvider)
    .tools
    .where((t) => t.kind == kind)
    .firstOrNull;

/// Shows the items of a chapter or a slide.
class DocItemsView extends StatelessWidget {
  const DocItemsView({super.key, required this.items});

  final List<DocItem> items;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final item in items)
        Padding(
          padding: const EdgeInsets.only(top: EripooSpacing.xs),
          child: switch (item) {
            DocParagraph(:final text) => Text(text),
            DocLabeled(:final label, :final text) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: context.textStyles.labelMedium),
                Text(text),
              ],
            ),
            DocBullet(:final text) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.circle, size: 6),
                ),
                const SizedBox(width: EripooSpacing.sm),
                Expanded(child: Text(text)),
              ],
            ),
          },
        ),
    ],
  );
}

/// A screen that needs the active project's synthesis.
class _SynthesisScaffold extends ConsumerWidget {
  const _SynthesisScaffold({required this.title, required this.body});

  final String title;
  final Widget Function(ProjectSynthesis s) body;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ref
          .watch(synthesisProvider)
          .when(
            loading: () => const EripooLoadingView(),
            error: (_, _) => const EripooErrorView(),
            data: (s) => s == null
                ? EripooMessageView(
                    icon: Icons.work_outline,
                    title: l10n.projectEmptyTitle,
                    message: l10n.projectEmptyBody,
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(
                      vertical: EripooSpacing.lg,
                    ),
                    children: [ReadableColumn(child: body(s))],
                  ),
          ),
    );
  }
}

/// The entrepreneur's file (business plan): the chapters already written
/// by the work, then the ones left to work on. Exported as it is: no
/// button makes up the missing chapters (CLAUDE.md §15).
class DossierScreen extends ConsumerWidget {
  const DossierScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tool = _tool(ref, ToolKind.businessPlan);
    return _SynthesisScaffold(
      title: tool == null ? l10n.navTools : contentText(context, tool.title),
      body: (s) {
        final parts = documentBuilder(context, ref, s).dossier();
        final ready = parts.where((p) => p.filled).toList();
        final missing = parts.where((p) => !p.filled).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.dossierIntro),
            const SizedBox(height: EripooSpacing.sm),
            Text(
              l10n.dossierProgress(
                context.formatter.fraction(ready.length, parts.length),
              ),
              style: context.textStyles.labelLarge,
            ),
            for (final part in ready) ...[
              const SizedBox(height: EripooSpacing.md),
              EripooCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(part.title, style: context.textStyles.titleSmall),
                    DocItemsView(items: part.items),
                  ],
                ),
              ),
            ],
            if (missing.isNotEmpty) ...[
              const SizedBox(height: EripooSpacing.xl),
              Text(l10n.dossierMissing, style: context.textStyles.titleMedium),
              for (final part in missing) ...[
                const SizedBox(height: EripooSpacing.sm),
                Text(part.title, style: context.textStyles.titleSmall),
                Text(
                  l10n.dossierChapterHint(part.key),
                  style: context.textStyles.bodySmall,
                ),
              ],
            ],
            const SizedBox(height: EripooSpacing.xl),
            EripooButton(
              label: l10n.exportPdf,
              icon: Icons.picture_as_pdf_outlined,
              onPressed: ready.isEmpty
                  ? null
                  : () => exportPdf(
                      context,
                      ref,
                      kind: PdfKind.dossier,
                      title: s.project.title,
                      parts: ready,
                      missing: missing,
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// A tool that is a project section written with help: the marketing plan
/// and the pitch.
class SectionToolScreen extends ConsumerWidget {
  const SectionToolScreen({
    super.key,
    required this.kind,
    required this.sectionKey,
  });

  final ToolKind kind;
  final String sectionKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tool = _tool(ref, kind);
    final schema = ref.watch(contentPackProvider).section(sectionKey);
    final project = ref.watch(activeProjectProvider).value;
    return _SynthesisScaffold(
      title: tool == null ? l10n.navTools : contentText(context, tool.title),
      body: (s) {
        final fields = s.sections[sectionKey] ?? const <String, Object?>{};
        final words = [
          for (final v in fields.values)
            ...?v?.toString().split(RegExp(r'\s+')).where((w) => w.isNotEmpty),
        ].length;
        // About 130 words a minute when speaking calmly.
        final seconds = (words * 60 + 129) ~/ 130;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (tool != null)
              for (final h in tool.help) ...[
                Text(contentText(context, h)),
                const SizedBox(height: EripooSpacing.sm),
              ],
            if (schema != null && project != null) ...[
              const SizedBox(height: EripooSpacing.md),
              ProjectSectionCard(
                project: project,
                schema: schema,
                fields: fields,
              ),
            ],
            if (kind == ToolKind.pitch && words > 0) ...[
              const SizedBox(height: EripooSpacing.md),
              Text(
                l10n.pitchSpeakingTime(seconds),
                style: context.textStyles.labelLarge,
              ),
              if (seconds > 90) Text(l10n.pitchTooLong),
            ],
          ],
        );
      },
    );
  }
}

/// The pitch deck: slides made from the work, previewed in landscape,
/// exported as a PDF.
class PitchDeckScreen extends ConsumerWidget {
  const PitchDeckScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tool = _tool(ref, ToolKind.pitchDeck);
    return _SynthesisScaffold(
      title: tool == null ? l10n.navTools : contentText(context, tool.title),
      body: (s) {
        final slides = documentBuilder(context, ref, s).pitchDeck();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.deckIntro),
            const SizedBox(height: EripooSpacing.sm),
            Text(
              l10n.deckCount(slides.length),
              style: context.textStyles.labelLarge,
            ),
            for (final (i, slide) in slides.indexed) ...[
              const SizedBox(height: EripooSpacing.md),
              Semantics(
                label: l10n.deckSlideNumber(i + 1),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: EripooCard(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            slide.title,
                            style: i == 0
                                ? context.textStyles.titleLarge
                                : context.textStyles.titleMedium,
                          ),
                          DocItemsView(items: slide.items),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: EripooSpacing.xl),
            EripooButton(
              label: l10n.exportPdf,
              icon: Icons.picture_as_pdf_outlined,
              onPressed: () => exportPdf(
                context,
                ref,
                kind: PdfKind.pitchDeck,
                title: s.project.title,
                parts: slides,
              ),
            ),
          ],
        );
      },
    );
  }
}
