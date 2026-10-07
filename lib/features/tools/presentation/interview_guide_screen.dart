import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../content/content_pack.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../quest/presentation/content_widgets.dart';
import '../../quest/presentation/journey_providers.dart';

/// The interview guide: content only (questions to ask, mistakes to
/// avoid), then a way to write the conversation down in the notebook.
class InterviewGuideScreen extends ConsumerWidget {
  const InterviewGuideScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tool = ref
        .watch(contentPackProvider)
        .tools
        .where((t) => t.kind == ToolKind.interviewGuide)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          tool == null ? l10n.navTools : contentText(context, tool.title),
        ),
      ),
      body: tool == null
          ? const EripooErrorView()
          : ListView(
              padding: const EdgeInsets.all(EripooSpacing.lg),
              children: [
                ReadableColumn(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(contentText(context, tool.summary)),
                      for (final section in tool.guide) ...[
                        const SizedBox(height: EripooSpacing.lg),
                        Text(
                          contentText(context, section.title),
                          style: context.textStyles.titleMedium,
                        ),
                        for (final item in section.items) ...[
                          const SizedBox(height: EripooSpacing.sm),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: Icon(Icons.check, size: 18),
                              ),
                              const SizedBox(width: EripooSpacing.sm),
                              Expanded(child: Text(contentText(context, item))),
                            ],
                          ),
                        ],
                      ],
                      const SizedBox(height: EripooSpacing.xl),
                      EripooButton(
                        label: l10n.guideNoteInterview,
                        icon: Icons.forum_outlined,
                        onPressed: () => context.go(AppRoutes.fieldNotes),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
