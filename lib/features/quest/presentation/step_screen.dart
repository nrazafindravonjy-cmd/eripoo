import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart' hide Block;

import '../../../app/router/app_router.dart';
import '../../../content/content_pack.dart';
import '../../../content/localized_text.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../missions/domain/mission_state.dart';
import '../application/journey_service.dart';
import '../domain/answer.dart';
import '../domain/step_session.dart';
import 'content_widgets.dart';
import 'journey_providers.dart';

/// Generic screen for any step: one block per screen, rendered by type
/// (docs/ARCHITECTURE.md §6). No screen is specific to a step.
class StepScreen extends ConsumerStatefulWidget {
  const StepScreen({super.key, required this.stepId});

  final String stepId;

  @override
  ConsumerState<StepScreen> createState() => _StepScreenState();
}

class _StepScreenState extends ConsumerState<StepScreen> {
  StepSession? _session;
  final _fields = <String, TextEditingController>{};
  String? _error;
  bool _busy = false;

  JourneyService get _journey => ref.read(journeyServiceProvider);

  @override
  void initState() {
    super.initState();
    // A message about the previous step ("Étape terminée") must not cover
    // this step's buttons (it rises above the keyboard on small phones).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
    });
    _load();
  }

  Future<void> _load() async {
    final journey = _journey;
    final step = journey.pack.step(widget.stepId);
    if (step == null) return;
    final plan = await journey.currentPlan();
    final answers = await journey.answersOf(widget.stepId);
    await journey.open(widget.stepId);
    if (!mounted) return;
    final session = StepSession(
      step: step,
      fastTrack: plan.step(widget.stepId)?.fastTrack ?? false,
      answers: answers,
    )..resume();
    for (final q in step.questions) {
      final a = answers[q.id];
      if (a != null && !a.isUnknown && !q.answer.isChoice) {
        _fields[q.id] = TextEditingController(text: '${a.value}');
      }
    }
    setState(() => _session = session);
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _field(String blockId) =>
      _fields.putIfAbsent(blockId, TextEditingController.new);

  Future<void> _save(QuestionBlock block, Answer answer) =>
      _journey.saveAnswer(widget.stepId, block.id, answer);

  /// Saves what is typed in the current field, if any. False if invalid.
  Future<bool> _commitField() async {
    final session = _session!;
    final block = session.current;
    if (block is! QuestionBlock || block.answer.isChoice) return true;
    final raw = _fields[block.id]?.text.trim() ?? '';
    if (raw.isEmpty) {
      return block.optional || session.answers.containsKey(block.id);
    }
    final Object? value = switch (block.answer.kind) {
      AnswerKind.text => raw,
      AnswerKind.number => num.tryParse(raw.replaceAll(',', '.')),
      AnswerKind.money => int.tryParse(raw.replaceAll(RegExp(r'[\s.]'), '')),
      _ => null,
    };
    try {
      await _save(block, session.answer(block, value));
      return true;
    } on ArgumentError {
      if (!mounted) return false;
      setState(() => _error = AppLocalizations.of(context).stepInvalidAnswer);
      return false;
    }
  }

  Future<void> _next() async {
    if (!await _commitField()) return;
    setState(() {
      _error = null;
      _session!.next();
    });
  }

  Future<void> _finish() async {
    final l10n = AppLocalizations.of(context);
    if (!await _commitField()) return;
    setState(() => _busy = true);
    final result = await _journey.complete(
      widget.stepId,
      fastTrack: _session!.fastTrack,
      provisionalProjectTitle: l10n.projectProvisionalTitle,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result) {
      case StepCompleted():
        _leave(l10n.stepCompleted);
      case MissingAnswers(:final blockIds):
        final session = _session!;
        final index = session.blocks.indexWhere((b) => blockIds.contains(b.id));
        setState(() {
          _error = l10n.stepMissingAnswers;
          while (index >= 0 && session.index > index) {
            session.back();
          }
        });
      case ConditionNotMet():
        setState(() => _error = l10n.stepWaitingMission);
    }
  }

  void _leave(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.home);
    }
  }

  Future<void> _onHelp(HelpAction action) async {
    final l10n = AppLocalizations.of(context);
    final session = _session!;
    final block = session.current;
    switch (action) {
      case HelpAction.dontKnow when block is QuestionBlock:
        _fields[block.id]?.clear();
        await _save(block, session.dontKnow(block));
        setState(() {
          _error = null;
          if (!session.isLast) session.next();
        });
      case HelpAction.dontUnderstand when block is QuestionBlock:
        setState(() => session.notUnderstood(block));
      case HelpAction.showExample when block is QuestionBlock:
        setState(() => session.showExample(block));
      case HelpAction.askHelp when block is QuestionBlock:
        setState(() => session.nextHint(block));
      case HelpAction.skipForNow:
        await _journey.skipForNow(widget.stepId);
        if (mounted) _leave(l10n.stepSkipped);
      case HelpAction.comeBackLater:
        await _journey.comeBackLater(widget.stepId);
        if (mounted) _leave(l10n.stepPostponed);
      default:
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final session = _session;
    final pack = ref.watch(contentPackProvider);
    final step = pack.step(widget.stepId);
    if (step == null) return const Scaffold(body: EripooErrorView());
    if (session == null) return const Scaffold(body: EripooLoadingView());
    final block = session.current;
    final isQuestion = block is QuestionBlock;
    final inDiagnostic =
        ref.read(contentPackProvider).questOfStep(widget.stepId)?.kind ==
        QuestKind.diagnostic;
    return Scaffold(
      appBar: AppBar(title: Text(contentText(context, step.title))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: EripooSpacing.lg),
          children: [
            ReadableColumn(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  EripooProgress(
                    done: session.index + 1,
                    total: session.blocks.length,
                  ),
                  const SizedBox(height: EripooSpacing.xl),
                  KeyedSubtree(
                    key: ValueKey(block.id),
                    child: _BlockView(
                      block: block,
                      session: session,
                      field: _field,
                      onChoice: (value) async {
                        final q = block as QuestionBlock;
                        await _save(q, session.answer(q, value));
                        setState(() => _error = null);
                      },
                      onOpenMission: (id) =>
                          context.push(AppRoutes.mission(id)),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: EripooSpacing.md),
                    Text(
                      _error!,
                      style: context.textStyles.bodyMedium?.copyWith(
                        color: context.colors.danger.base,
                      ),
                    ),
                  ],
                  const SizedBox(height: EripooSpacing.xl),
                  EripooButton(
                    label: session.isLast ? l10n.stepFinish : l10n.stepNext,
                    expand: true,
                    isLoading: _busy,
                    onPressed: session.isLast ? _finish : _next,
                  ),
                  const SizedBox(height: EripooSpacing.sm),
                  // Side by side when they fit, stacked otherwise (narrow
                  // phones, large text).
                  OverflowBar(
                    alignment: session.isFirst
                        ? MainAxisAlignment.end
                        : MainAxisAlignment.spaceBetween,
                    overflowAlignment: OverflowBarAlignment.end,
                    overflowSpacing: EripooSpacing.xs,
                    children: [
                      if (!session.isFirst)
                        EripooButton(
                          label: l10n.stepBack,
                          icon: Icons.arrow_back,
                          variant: EripooButtonVariant.tertiary,
                          onPressed: () => setState(() {
                            _error = null;
                            session.back();
                          }),
                        ),
                      // The diagnostic is not set aside: the journey starts
                      // after it, and "I don't know" is always possible.
                      if (isQuestion || !inDiagnostic)
                        EripooHelpButton(
                          onSelected: _onHelp,
                          actions: [
                            if (isQuestion) ...[
                              HelpAction.dontKnow,
                              HelpAction.dontUnderstand,
                              HelpAction.showExample,
                              HelpAction.askHelp,
                            ],
                            if (!inDiagnostic) ...[
                              HelpAction.skipForNow,
                              HelpAction.comeBackLater,
                            ],
                          ],
                        ),
                    ],
                  ),
                  if (needsReviewNote(context, _textsOf(block)))
                    const ContentReviewNote(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Iterable<LocalizedText> _textsOf(Block block) => switch (block) {
  TextBlock(:final body) ||
  ExampleBlock(:final body) ||
  TipBlock(:final body) => [body],
  TermBlock() => [block.plain, block.term, block.definition],
  QuestionBlock() => [
    block.prompt,
    for (final o in block.answer.options) o.label,
  ],
  SynthesisBlock() => [block.intro],
  MissionBlock() => const [],
};

class _BlockView extends ConsumerWidget {
  const _BlockView({
    required this.block,
    required this.session,
    required this.field,
    required this.onChoice,
    required this.onOpenMission,
  });

  final Block block;
  final StepSession session;
  final TextEditingController Function(String blockId) field;
  final ValueChanged<Object> onChoice;
  final ValueChanged<String> onOpenMission;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final styles = context.textStyles;
    String t(LocalizedText text) => contentText(context, text);
    return switch (block) {
      TextBlock(:final body) => Text(t(body), style: styles.bodyLarge),
      ExampleBlock(:final body) => _Panel(
        icon: Icons.storefront_outlined,
        title: l10n.stepExample,
        body: t(body),
      ),
      TipBlock(:final body) => _Panel(
        icon: Icons.lightbulb_outline,
        title: null,
        body: t(body),
      ),
      TermBlock() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t((block as TermBlock).plain), style: styles.bodyLarge),
          const SizedBox(height: EripooSpacing.md),
          Text(l10n.stepTermIntro, style: styles.labelLarge),
          Text(t((block as TermBlock).term), style: styles.titleLarge),
          const SizedBox(height: EripooSpacing.xs),
          Text(t((block as TermBlock).definition), style: styles.bodyMedium),
        ],
      ),
      QuestionBlock() => _QuestionView(
        block: block as QuestionBlock,
        session: session,
        controller: field(block.id),
        onChoice: onChoice,
      ),
      SynthesisBlock() => _SynthesisView(
        block: block as SynthesisBlock,
        session: session,
      ),
      MissionBlock(:final missionId) => _MissionCard(
        missionId: missionId,
        onOpen: () => onOpenMission(missionId),
      ),
    };
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String? title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(EripooSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: BorderRadius.circular(EripooRadii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colors.brand.base),
          const SizedBox(width: EripooSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Text(title!, style: context.textStyles.labelLarge),
                Text(body, style: context.textStyles.bodyLarge),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestionView extends StatelessWidget {
  const _QuestionView({
    required this.block,
    required this.session,
    required this.controller,
    required this.onChoice,
  });

  final QuestionBlock block;
  final StepSession session;
  final TextEditingController controller;
  final ValueChanged<Object> onChoice;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    String t(LocalizedText text) => contentText(context, text);
    final help = session.help(block.id);
    final answer = session.answers[block.id];
    final spec = block.answer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t(block.prompt), style: context.textStyles.titleLarge),
        if (help.rephraseLevel > 0) ...[
          const SizedBox(height: EripooSpacing.md),
          _Panel(
            icon: Icons.record_voice_over_outlined,
            title: l10n.stepRephrase,
            body: t(block.help.rephrase[help.rephraseLevel - 1]),
          ),
        ],
        if (help.showExample) ...[
          const SizedBox(height: EripooSpacing.md),
          _Panel(
            icon: Icons.storefront_outlined,
            title: l10n.stepExample,
            body: t(block.help.example),
          ),
        ],
        for (var i = 0; i < help.hintsShown; i++) ...[
          const SizedBox(height: EripooSpacing.md),
          _Panel(
            icon: Icons.lightbulb_outline,
            title: l10n.stepHint,
            body: t(block.help.hints[i]),
          ),
        ],
        if (help.stuck) ...[
          const SizedBox(height: EripooSpacing.md),
          _Panel(
            icon: Icons.favorite_border,
            title: l10n.stepStuckTitle,
            body: l10n.stepStuckBody,
          ),
        ],
        const SizedBox(height: EripooSpacing.lg),
        if (answer != null && answer.isUnknown)
          Padding(
            padding: const EdgeInsets.only(bottom: EripooSpacing.md),
            child: Text(
              l10n.stepUnknownAnswer,
              style: context.textStyles.bodyMedium,
            ),
          ),
        switch (spec.kind) {
          AnswerKind.choice => Column(
            children: [
              for (final o in spec.options)
                _OptionTile(
                  label: t(o.label),
                  selected: answer?.value == o.value,
                  multi: false,
                  onTap: () => onChoice(o.value),
                ),
            ],
          ),
          AnswerKind.multiChoice => Column(
            children: [
              for (final o in spec.options)
                _OptionTile(
                  label: t(o.label),
                  selected:
                      (answer?.value as List<String>?)?.contains(o.value) ??
                      false,
                  multi: true,
                  onTap: () {
                    final current = {...?(answer?.value as List<String>?)};
                    if (!current.remove(o.value)) current.add(o.value);
                    if (current.isNotEmpty) {
                      onChoice([
                        for (final opt in spec.options)
                          if (current.contains(opt.value)) opt.value,
                      ]);
                    }
                  },
                ),
            ],
          ),
          AnswerKind.text => EripooTextField(
            label: l10n.stepYourAnswer,
            controller: controller,
            isOptional: block.optional,
            minLines: 3,
            maxLines: 8,
            maxLength: spec.maxLength,
            keyboardType: TextInputType.multiline,
          ),
          AnswerKind.number => EripooTextField(
            label: l10n.stepNumberLabel,
            controller: controller,
            isOptional: block.optional,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          AnswerKind.money => EripooTextField(
            label: l10n.stepMoneyLabel,
            controller: controller,
            isOptional: block.optional,
            keyboardType: TextInputType.number,
          ),
        },
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.label,
    required this.selected,
    required this.multi,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool multi;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: EripooSpacing.sm),
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected ? colors.brand.container : colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(EripooRadii.md),
            side: BorderSide(
              color: selected ? colors.brand.base : colors.borderStrong,
              width: selected ? 2 : 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(EripooRadii.md),
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: EripooLayout.primaryActionHeight,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: EripooSpacing.lg,
                  vertical: EripooSpacing.md,
                ),
                child: Row(
                  children: [
                    Icon(
                      multi
                          ? (selected
                                ? Icons.check_box
                                : Icons.check_box_outline_blank)
                          : (selected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked),
                      color: selected
                          ? colors.brand.base
                          : colors.textSecondary,
                    ),
                    const SizedBox(width: EripooSpacing.md),
                    Expanded(
                      child: Text(label, style: context.textStyles.bodyLarge),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows back what the user wrote in this step.
class _SynthesisView extends StatelessWidget {
  const _SynthesisView({required this.block, required this.session});

  final SynthesisBlock block;
  final StepSession session;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    String t(LocalizedText text) => contentText(context, text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t(block.intro), style: context.textStyles.titleLarge),
        const SizedBox(height: EripooSpacing.lg),
        for (final id in block.shows)
          if (session.step.block(id) case final QuestionBlock q)
            Padding(
              padding: const EdgeInsets.only(bottom: EripooSpacing.md),
              child: EripooCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t(q.prompt), style: context.textStyles.labelLarge),
                    const SizedBox(height: EripooSpacing.xs),
                    Text(
                      _display(context, q, session.answers[id], l10n),
                      style: context.textStyles.bodyLarge,
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  static String _display(
    BuildContext context,
    QuestionBlock q,
    Answer? answer,
    AppLocalizations l10n,
  ) {
    if (answer == null) return l10n.stepNoAnswer;
    if (answer.isUnknown) return l10n.stepUnknownAnswer;
    String label(String value) {
      for (final o in q.answer.options) {
        if (o.value == value) return contentText(context, o.label);
      }
      return value;
    }

    return switch (answer.type) {
      AnswerType.choice => label(answer.value! as String),
      AnswerType.multiChoice =>
        (answer.value! as List<String>).map(label).join(', '),
      AnswerType.money => context.formatter.money(answer.value! as int),
      _ => '${answer.value}',
    };
  }
}

class _MissionCard extends ConsumerWidget {
  const _MissionCard({required this.missionId, required this.onOpen});

  final String missionId;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final template = ref.watch(contentPackProvider).mission(missionId)!;
    final missions = ref.watch(missionsProvider).value ?? const [];
    final instance = missions.where((m) => m.templateId == missionId);
    final status = instance.isEmpty ? null : instance.single.status;
    return EripooCard(
      semanticLabel: contentText(context, template.title),
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.missionLabel, style: context.textStyles.labelLarge),
          Text(
            contentText(context, template.title),
            style: context.textStyles.titleLarge,
          ),
          const SizedBox(height: EripooSpacing.xs),
          Text(contentText(context, template.objective)),
          const SizedBox(height: EripooSpacing.sm),
          Text(
            l10n.missionDuration('${template.durationMinutes}'),
            style: context.textStyles.bodySmall,
          ),
          if (status != null)
            Text(
              missionStatusLabel(l10n, status),
              style: context.textStyles.bodySmall,
            ),
          const SizedBox(height: EripooSpacing.md),
          EripooButton(
            label: l10n.missionOpen,
            variant: EripooButtonVariant.secondary,
            onPressed: onOpen,
          ),
        ],
      ),
    );
  }
}

String missionStatusLabel(AppLocalizations l10n, MissionStatus status) =>
    switch (status) {
      MissionStatus.proposed => l10n.missionAccept,
      MissionStatus.accepted ||
      MissionStatus.inProgress => l10n.missionStatusAccepted,
      MissionStatus.submitted => l10n.missionStatusSubmitted,
      MissionStatus.completed => l10n.missionStatusCompleted,
      MissionStatus.abandoned => l10n.missionStatusAbandoned,
    };
