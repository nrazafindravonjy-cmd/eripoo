import '../core/i18n/app_language.dart';
import 'content_pack.dart';
import 'localized_text.dart';
import 'progress_state.dart';
import 'rules.dart';

/// Result of [validatePack]. Errors block a pack; warnings are listed for
/// authors; review counts show what still needs a native reviewer.
class ValidationReport {
  final errors = <String>[];
  final warnings = <String>[];

  /// Texts per language and review status (all texts of the pack).
  final reviewCounts = <AppLanguage, Map<ReviewStatus, int>>{};

  /// Texts with no version in a language (shown through the fallback).
  final missing = <AppLanguage, int>{};

  bool get ok => errors.isEmpty;
}

/// Most consecutive questions without anything else on screen
/// (docs/PRODUCT_ARCHITECTURE.md §3.4).
const maxConsecutiveQuestions = 5;

/// Checks what the parser cannot: references, rules against the pack,
/// anti-blocking guardrails and privacy (free text never becomes a fact).
ValidationReport validatePack(ContentPack pack) {
  final report = ValidationReport();
  void error(String where, String problem) =>
      report.errors.add('$where: $problem');
  void warn(String where, String problem) =>
      report.warnings.add('$where: $problem');

  // ---- unique identifiers
  final questIds = <String>{};
  final stepIds = <String>{};
  final orders = <int>{};
  for (final quest in pack.quests) {
    if (!questIds.add(quest.id)) error(quest.id, 'duplicate quest id');
    if (quest.kind == QuestKind.journey && !orders.add(quest.order)) {
      error(quest.id, 'duplicate quest order ${quest.order}');
    }
    for (final step in quest.steps) {
      if (!stepIds.add(step.id)) error(step.id, 'duplicate step id');
      if (!step.id.startsWith('${quest.id}.')) {
        error(step.id, 'step id must start with "${quest.id}."');
      }
      final blockIds = <String>{};
      for (final block in step.blocks) {
        if (!blockIds.add(block.id)) {
          error('${step.id}/${block.id}', 'duplicate block id');
        }
      }
    }
  }
  final missionIds = <String>{};
  for (final mission in pack.missions) {
    if (!missionIds.add(mission.id)) error(mission.id, 'duplicate mission id');
  }
  if (pack.quests.where((q) => q.kind == QuestKind.diagnostic).length > 1) {
    error('pack', 'at most one diagnostic');
  }

  // ---- facts produced by the pack, with their possible values
  final factValues = <String, Set<Object>?>{}; // null: any number
  for (final step in pack.steps) {
    for (final output in step.outputs) {
      final target = output.target;
      if (target is! FactTarget) continue;
      final block = step.block(output.fromBlock);
      if (block is! QuestionBlock) continue; // reported below
      factValues[target.key] = block.answer.kind == AnswerKind.choice
          ? {for (final o in block.answer.options) o.value, unknownFactValue}
          : null;
    }
  }

  // ---- rules
  void checkRule(String where, Rule? rule) {
    if (rule == null) return;
    for (final ref in rule.references) {
      switch (ref.kind) {
        case RefKind.step:
          if (!stepIds.contains(ref.id)) {
            error(where, 'unknown step ${ref.id}');
          }
        case RefKind.quest:
          if (!questIds.contains(ref.id)) {
            error(where, 'unknown quest ${ref.id}');
          }
        case RefKind.mission:
          if (!missionIds.contains(ref.id)) {
            error(where, 'unknown mission ${ref.id}');
          }
        case RefKind.fact:
          if (!factValues.containsKey(ref.id)) {
            error(where, 'fact ${ref.id} is written by no step');
          }
      }
    }
    void checkValues(Rule r) {
      switch (r) {
        case AllRule(:final rules) || AnyRule(:final rules):
          rules.forEach(checkValues);
        case NotRule(:final rule):
          checkValues(rule);
        case StepRule(:final statuses):
          // Planner results, not stored state: a rule cannot read them.
          if (statuses.contains(StepStatus.locked) ||
              statuses.contains(StepStatus.available)) {
            error(
              where,
              'a rule cannot test locked/available (planner results)',
            );
          }
        case FactRule():
          final allowed = factValues[r.key];
          if (allowed == null) return;
          for (final v in [r.eq, r.ne, ...?r.inValues]) {
            if (v != null && !allowed.contains(v)) {
              error(where, 'fact ${r.key} never takes the value $v');
            }
          }
        default:
      }
    }

    checkValues(rule);
  }

  final usedMissions = <String>{};
  final usedTypes = <BlockType>{};
  for (final quest in pack.quests) {
    checkRule('${quest.id}.available_when', quest.availableWhen);
    checkRule('${quest.id}.fast_track_when', quest.fastTrackWhen);
    if (!maturityStages.contains(quest.maturity)) {
      error(quest.id, 'unknown maturity');
    }
    for (final step in quest.steps) {
      final where = step.id;
      checkRule('$where.available_when', step.availableWhen);
      checkRule('$where.complete_when', step.completeWhen);
      checkRule('$where.fast_track_when', step.fastTrackWhen);

      final questions = {for (final q in step.questions) q.id: q};
      var consecutive = 0;
      for (final block in step.blocks) {
        usedTypes.add(block.type);
        if (block is QuestionBlock) {
          consecutive++;
          if (consecutive > maxConsecutiveQuestions) {
            error(
              where,
              'more than $maxConsecutiveQuestions questions in a row',
            );
          }
        } else {
          consecutive = 0;
        }
        switch (block) {
          case MissionBlock(:final missionId):
            usedMissions.add(missionId);
            if (!missionIds.contains(missionId)) {
              error('$where/${block.id}', 'unknown mission $missionId');
            }
          case SynthesisBlock(:final shows):
            for (final id in shows) {
              if (!questions.containsKey(id)) {
                error(
                  '$where/${block.id}',
                  'shows $id, not a question of the step',
                );
              }
            }
          case QuestionBlock(:final answer):
            if (answer.kind == AnswerKind.text && answer.maxLength == null) {
              warn('$where/${block.id}', 'free text without max_length');
            }
          default:
        }
      }
      if (step.type == StepType.reflect &&
          step.blocks.last is! SynthesisBlock) {
        error(where, 'a reflect step ends with a synthesis');
      }
      for (final id in step.fastTrackBlocks) {
        if (!questions.containsKey(id)) {
          error(where, 'fast_track_blocks: $id is not a question of the step');
        }
      }
      for (final output in step.outputs) {
        final q = questions[output.fromBlock];
        if (q == null) {
          error(
            where,
            'output from ${output.fromBlock}, not a question of the step',
          );
          continue;
        }
        switch (output.target) {
          case FactTarget(:final key):
            if (q.answer.kind == AnswerKind.text ||
                q.answer.kind == AnswerKind.multiChoice) {
              error(
                where,
                'fact $key from a ${q.answer.kind.name} answer '
                '(facts are tokens or numbers, never free text)',
              );
            }
          case ProjectTitleTarget():
            if (q.answer.kind != AnswerKind.text) {
              error(where, 'the project title comes from a text answer');
            }
          case SectionTarget(:final section, :final field):
            if (pack.sections.isNotEmpty &&
                pack.section(section)?.field(field) == null) {
              error(
                where,
                'section field $section.$field is not declared in sections',
              );
            }
        }
      }
      // A fast-tracked step must still collect its deliverable.
      final fastTrack = step.fastTrackWhen ?? quest.fastTrackWhen;
      if (fastTrack != null && step.outputs.isNotEmpty) {
        final kept = step.fastTrackBlocks.isEmpty
            ? step.outputs.map((o) => o.fromBlock).toSet()
            : step.fastTrackBlocks.toSet();
        for (final output in step.outputs) {
          if (!kept.contains(output.fromBlock)) {
            error(
              where,
              'fast track would skip the deliverable ${output.fromBlock}',
            );
          }
        }
      }
    }
  }
  for (final mission in pack.missions) {
    checkRule('${mission.id}.complete_when', mission.completeWhen);
    if (!usedMissions.contains(mission.id)) {
      warn(mission.id, 'mission proposed by no step');
    }
  }

  final diagnostic = pack.diagnostic;
  if (diagnostic != null) {
    final titles = diagnostic.steps
        .expand((s) => s.outputs)
        .where((o) => o.target is ProjectTitleTarget)
        .length;
    if (titles != 1) {
      error(diagnostic.id, 'the diagnostic names the project once');
    }
  }

  final sectionKeys = <String>{};
  for (final section in pack.sections) {
    if (!sectionKeys.add(section.key)) {
      error('sections', 'duplicate section ${section.key}');
    }
    final fieldKeys = <String>{};
    for (final f in section.fields) {
      if (!fieldKeys.add(f.key)) {
        error('sections', 'duplicate field ${section.key}.${f.key}');
      }
    }
  }

  // ---- tools (CLAUDE.md §20): each kind once, rules valid, help always
  // readable, a hint for every locked tool.
  final toolIds = <String>{};
  final toolKinds = <ToolKind>{};
  for (final tool in pack.tools) {
    if (!toolIds.add(tool.id)) error(tool.id, 'duplicate tool id');
    if (!toolKinds.add(tool.kind)) {
      error(tool.id, 'tool ${tool.kind.name} declared twice');
    }
    if (tool.help.isEmpty) error(tool.id, 'a tool needs help text');
    checkRule('${tool.id}.unlock', tool.unlock);
    if (tool.unlock != null && tool.unlockHint == null) {
      error(tool.id, 'a tool with an unlock rule needs an unlock_hint');
    }
    if (tool.kind == ToolKind.interviewGuide && tool.guide.isEmpty) {
      error(tool.id, 'the interview guide needs its guide sections');
    }
  }

  for (final type in usedTypes) {
    if (!pack.blockTypes.contains(type)) {
      error('pack', 'block type ${type.name} used but not declared');
    }
  }

  // ---- texts: languages and review status
  for (final text in allTexts(pack)) {
    for (final language in AppLanguage.values) {
      if (!text.texts.containsKey(language)) {
        report.missing[language] = (report.missing[language] ?? 0) + 1;
        continue;
      }
      final counts = report.reviewCounts.putIfAbsent(language, () => {});
      final status = text.statusOf(language);
      counts[status] = (counts[status] ?? 0) + 1;
    }
    if (!text.texts.containsKey(AppLanguage.fr)) {
      error('text "${text.texts.values.first}"', 'French reference missing');
    }
  }
  return report;
}

/// Every localized text of the pack.
Iterable<LocalizedText> allTexts(ContentPack pack) sync* {
  for (final quest in pack.quests) {
    yield quest.title;
    yield quest.summary;
    for (final step in quest.steps) {
      yield step.title;
      for (final block in step.blocks) {
        switch (block) {
          case TextBlock(:final body) ||
              ExampleBlock(:final body) ||
              TipBlock(:final body):
            yield body;
          case TermBlock():
            yield block.plain;
            yield block.term;
            yield block.definition;
          case QuestionBlock():
            yield block.prompt;
            for (final o in block.answer.options) {
              yield o.label;
            }
            yield* block.help.rephrase;
            yield block.help.example;
            yield* block.help.hints;
          case SynthesisBlock():
            yield block.intro;
          case MissionBlock():
        }
      }
    }
  }
  for (final section in pack.sections) {
    yield section.title;
    for (final f in section.fields) {
      yield f.label;
    }
  }
  for (final mission in pack.missions) {
    yield mission.title;
    yield mission.objective;
    yield* mission.instructions;
    yield mission.deliverable;
    if (mission.example != null) yield mission.example!;
  }
  for (final tool in pack.tools) {
    yield tool.title;
    yield tool.summary;
    yield* tool.help;
    if (tool.unlockHint != null) yield tool.unlockHint!;
    for (final g in tool.guide) {
      yield g.title;
      yield* g.items;
    }
  }
}
