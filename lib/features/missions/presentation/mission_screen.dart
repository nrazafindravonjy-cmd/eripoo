import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../quest/presentation/content_widgets.dart';
import '../../quest/presentation/journey_providers.dart';
import '../../quest/presentation/step_screen.dart' show missionStatusLabel;
import '../../usage/domain/usage_event.dart';
import '../../usage/presentation/usage_providers.dart';
import '../domain/mission_state.dart';

/// Longest reflection kept for a mission (free text, stays on the device
/// and in encrypted sync only).
const missionReflectionMaxLength = 2000;

/// One mission: what to do, then accept, hand in, abandon or take up again.
class MissionScreen extends ConsumerStatefulWidget {
  const MissionScreen({super.key, required this.missionId});

  final String missionId;

  @override
  ConsumerState<MissionScreen> createState() => _MissionScreenState();
}

class _MissionScreenState extends ConsumerState<MissionScreen> {
  final _reflection = TextEditingController();
  bool _busy = false;
  bool _empty = false;
  bool _prefilled = false;

  @override
  void dispose() {
    _reflection.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (_reflection.text.trim().isEmpty) {
      setState(() => _empty = true);
      return;
    }
    setState(() => _empty = false);
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await _run(() async {
      final status = await ref
          .read(journeyServiceProvider)
          .submitMission(widget.missionId, _reflection.text);
      messenger.showSnackBar(
        SnackBar(content: Text(missionStatusLabel(l10n, status))),
      );
      if (status == MissionStatus.completed) {
        unawaited(ref.read(usageRecorderProvider)(UsageEvent.missionCompleted));
      }
      // Back to the step that proposed it, which can now be finished.
      if (status == MissionStatus.completed && mounted && context.canPop()) {
        context.pop();
      }
    });
  }

  Future<void> _abandon() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showEripooConfirmDialog(
      context,
      title: l10n.missionAbandonConfirmTitle,
      message: l10n.missionAbandonConfirmBody,
      confirmLabel: l10n.missionAbandon,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await _run(
      () => ref.read(journeyServiceProvider).abandonMission(widget.missionId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final template = ref.watch(contentPackProvider).mission(widget.missionId);
    if (template == null) {
      return Scaffold(appBar: AppBar(), body: const EripooErrorView());
    }
    final missions = ref.watch(missionsProvider);
    final instances = (missions.value ?? const <MissionInstance>[]).where(
      (m) => m.templateId == widget.missionId,
    );
    final instance = instances.isEmpty ? null : instances.single;
    final status = instance?.status ?? MissionStatus.proposed;
    if (!_prefilled && instance?.reflection != null) {
      _prefilled = true;
      _reflection.text = instance!.reflection!;
    }
    return Scaffold(
      appBar: AppBar(title: Text(l10n.missionLabel)),
      body: missions.isLoading && !missions.hasValue
          ? const EripooLoadingView()
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: EripooSpacing.lg),
              children: [
                ReadableColumn(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        contentText(context, template.title),
                        style: context.textStyles.headlineSmall,
                      ),
                      const SizedBox(height: EripooSpacing.sm),
                      Text(
                        contentText(context, template.objective),
                        style: context.textStyles.bodyLarge,
                      ),
                      const SizedBox(height: EripooSpacing.sm),
                      Wrap(
                        spacing: EripooSpacing.sm,
                        runSpacing: EripooSpacing.xs,
                        children: [
                          Chip(
                            label: Text(
                              l10n.missionDuration(
                                '${template.durationMinutes}',
                              ),
                            ),
                          ),
                          if (template.realWorld)
                            Chip(label: Text(l10n.missionRealWorld)),
                          if (instance != null)
                            Chip(label: Text(missionStatusLabel(l10n, status))),
                        ],
                      ),
                      if (needsReviewNote(context, [
                        template.title,
                        template.objective,
                        ...template.instructions,
                        template.deliverable,
                      ]))
                        const ContentReviewNote(),
                      const SizedBox(height: EripooSpacing.lg),
                      Text(
                        l10n.missionInstructions,
                        style: context.textStyles.titleMedium,
                      ),
                      const SizedBox(height: EripooSpacing.sm),
                      for (final (i, line) in template.instructions.indexed)
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: EripooSpacing.sm,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: EripooSpacing.xl,
                                child: Text(
                                  context.formatter.integer(i + 1),
                                  style: context.textStyles.labelLarge,
                                ),
                              ),
                              Expanded(child: Text(contentText(context, line))),
                            ],
                          ),
                        ),
                      if (template.example case final example?) ...[
                        const SizedBox(height: EripooSpacing.sm),
                        EripooCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.stepExample,
                                style: context.textStyles.labelLarge,
                              ),
                              Text(contentText(context, example)),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: EripooSpacing.lg),
                      Text(
                        l10n.missionDeliverable,
                        style: context.textStyles.titleMedium,
                      ),
                      const SizedBox(height: EripooSpacing.sm),
                      Text(contentText(context, template.deliverable)),
                      const SizedBox(height: EripooSpacing.xl),
                      ..._actions(l10n, status),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  List<Widget> _actions(AppLocalizations l10n, MissionStatus status) {
    final service = ref.read(journeyServiceProvider);
    switch (status) {
      case MissionStatus.proposed:
        return [
          EripooButton(
            label: l10n.missionAccept,
            expand: true,
            isLoading: _busy,
            onPressed: () =>
                _run(() => service.acceptMission(widget.missionId)),
          ),
        ];
      case MissionStatus.abandoned:
        return [
          EripooButton(
            label: l10n.missionTakeUpAgain,
            expand: true,
            isLoading: _busy,
            onPressed: () =>
                _run(() => service.acceptMission(widget.missionId)),
          ),
        ];
      case MissionStatus.completed:
        return [
          EripooMessageView(
            icon: Icons.emoji_events_outlined,
            title: l10n.missionStatusCompleted,
            message: _reflection.text,
          ),
        ];
      case MissionStatus.accepted ||
          MissionStatus.inProgress ||
          MissionStatus.submitted:
        return [
          EripooTextField(
            label: l10n.missionReflectionLabel,
            controller: _reflection,
            minLines: 3,
            maxLines: 8,
            maxLength: missionReflectionMaxLength,
            errorText: _empty ? l10n.stepMissingAnswers : null,
            enabled: !_busy,
          ),
          const SizedBox(height: EripooSpacing.md),
          EripooButton(
            label: l10n.missionSubmit,
            expand: true,
            isLoading: _busy,
            onPressed: _submit,
          ),
          const SizedBox(height: EripooSpacing.sm),
          EripooButton(
            label: l10n.missionAbandon,
            variant: EripooButtonVariant.tertiary,
            expand: true,
            onPressed: _busy ? null : _abandon,
          ),
        ];
    }
  }
}
