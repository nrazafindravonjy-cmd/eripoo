// The pack embedded in the app (assets/content/base_pack.json, built from
// content/ by tool/content_build.dart): it must parse, validate without
// error or warning, and state honestly what is still to be reviewed.
import 'dart:convert';
import 'dart:io';

import 'package:eripoo/content/content_pack.dart';
import 'package:eripoo/content/content_validator.dart';
import 'package:eripoo/content/formalization.dart';
import 'package:eripoo/content/localized_text.dart';
import 'package:eripoo/content/planner.dart';
import 'package:eripoo/content/progress_state.dart';
import 'package:eripoo/core/i18n/app_language.dart';
import 'package:eripoo/features/quest/presentation/journey_providers.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/journey_overrides.dart';

void main() {
  final pack = basePack();

  test('validates without errors or warnings', () {
    final report = validatePack(pack);
    expect(report.errors, isEmpty);
    expect(report.warnings, isEmpty);
  });

  test('a diagnostic of at most 10 screens, then journey quests', () {
    final diagnostic = pack.diagnostic!;
    final screens = diagnostic.steps.fold<int>(
      0,
      (n, s) => n + s.blocks.length,
    );
    expect(screens, lessThanOrEqualTo(10));
    // Facts only from choices (never free text) in the diagnostic.
    for (final step in diagnostic.steps) {
      for (final q in step.questions) {
        if (q.answer.kind != AnswerKind.text) continue;
        expect(
          step.outputs.where((o) => o.fromBlock == q.id).single.target,
          isA<ProjectTitleTarget>(),
        );
      }
    }
    expect(pack.journey, isNotEmpty);
    expect(pack.missions, isNotEmpty);
  });

  test('every text has French and English', () {
    final report = validatePack(pack);
    for (final language in AppLanguage.values) {
      expect(report.missing[language] ?? 0, 0, reason: language.name);
    }
  });

  test('nothing is presented as reviewed before a person reviewed it', () {
    // Phase 3 drafts (DEVELOPMENT_PLAN D14): French and English still
    // need a human review.
    for (final text in allTexts(pack)) {
      expect(text.statusOf(AppLanguage.fr), ReviewStatus.needsReview);
      expect(text.statusOf(AppLanguage.en), ReviewStatus.needsReview);
    }
  });

  test('examples and missions contain no contact data', () {
    final phone = RegExp(r'(\+?261|\b03[2-9])[\s.]?\d{2}');
    final email = RegExp(r'[\w.+-]+@[\w-]+\.\w+');
    // Exception: an office's public contact, stated by its official source
    // (regulatory facts only, never advice, examples or missions).
    final sourced = {
      for (final t
          in pack.formalization?.topics ?? const <FormalizationTopic>[])
        for (final f in t.facts) f.text,
      // The publisher's own contact, required in the legal texts (law
      // 2014-038 art. 27, law 2015-014 art. 31).
      for (final d in pack.legal?.documents ?? const <LegalDocument>[])
        ...d.body,
    };
    for (final text in allTexts(pack)) {
      if (sourced.contains(text)) continue;
      for (final value in text.texts.values) {
        expect(phone.hasMatch(value), isFalse, reason: value);
        expect(email.hasMatch(value), isFalse, reason: value);
      }
    }
  });

  test('a plan can be computed on first launch', () {
    final p = plan(
      PlannerInput(
        pack: pack,
        now: DateTime.utc(2026, 10, 6),
        facts: const {},
        steps: const {},
        missions: const {},
      ),
    );
    expect(p.next!.step.id, pack.diagnostic!.steps.first.id);
  });

  test('without an idea, the journey starts with the introductory quests', () {
    PlannedStep? next(String profile) => plan(
      PlannerInput(
        pack: pack,
        now: DateTime.utc(2026, 10, 6),
        facts: {'diag.entry_profile': profile},
        steps: {
          for (final s in pack.diagnostic!.steps)
            s.id: const StepRecord(StepStatus.completed),
        },
      ),
    ).next;
    expect(next('no_idea')!.step.id, 'q13.s01');
    expect(next('vague_idea')!.step.id, 'q01.s01');
    // Not listed while locked, so other profiles never see a dead end.
    expect(pack.journey.where((q) => q.hideWhenLocked).map((q) => q.id), [
      'q13',
      'q14',
      'q15',
    ]);
  });

  test('the asset is the build of content/ (JSON, stable form)', () {
    final raw = File(basePackAsset).readAsStringSync();
    // Same formatting as the build tool, so --check in CI is meaningful.
    final reencoded =
        '${const JsonEncoder.withIndent(' ').convert(jsonDecode(raw))}\n';
    expect(raw, reencoded);
  });

  test('the first quest follows the chosen door: problem or desire', () {
    const done = StepRecord(StepStatus.completed);
    List<String> stepsOf(String? origin) {
      final p = plan(
        PlannerInput(
          pack: pack,
          now: DateTime.utc(2026, 10, 25),
          facts: {'diag.entry_profile': 'vague_idea', 'idea.origin': ?origin},
          steps: {for (final s in pack.diagnostic!.steps) s.id: done},
        ),
      );
      return [
        for (final s in p.quests.firstWhere((q) => q.quest.id == 'q01').steps)
          s.step.id,
      ];
    }

    expect(stepsOf('desire'), ['q01.s01', 'q01.s05', 'q01.s06', 'q01.s07']);
    expect(stepsOf('problem'), ['q01.s01', 'q01.s05', 'q01.s02', 'q01.s03']);
    // Before the choice (and for journeys started earlier): the problem door.
    expect(stepsOf(null), ['q01.s01', 'q01.s05', 'q01.s02', 'q01.s03']);
  });

  test('without an idea, the first quest waits for quest 15', () {
    final p = plan(
      PlannerInput(
        pack: pack,
        now: DateTime.utc(2026, 10, 25),
        facts: const {'diag.entry_profile': 'no_idea'},
        steps: {
          for (final s in pack.diagnostic!.steps)
            s.id: const StepRecord(StepStatus.completed),
        },
      ),
    );
    expect(p.quests.firstWhere((q) => q.quest.id == 'q01').available, isFalse);
    expect(p.quests.firstWhere((q) => q.quest.id == 'q13').available, isTrue);
  });

  test('people who already sell get the "grow my activity" journey', () {
    List<String> questsOf(String profile, String sector) => [
      for (final q in plan(
        PlannerInput(
          pack: pack,
          now: DateTime.utc(2026, 10, 25),
          facts: {'diag.entry_profile': profile, 'diag.sector': sector},
          steps: {
            for (final s in pack.diagnostic!.steps)
              s.id: const StepRecord(StepStatus.completed),
          },
        ),
      ).quests)
        if (!q.quest.hideWhenLocked || q.available) q.quest.id,
    ];

    final grow = questsOf('existing_customers', 'trade');
    expect(grow, containsAll(['q11', 'q16', 'q21', 'q23']));
    expect(grow, isNot(contains('q01')));
    expect(grow, isNot(contains('q12')));
    // Stock only matters for trade, food and crafts.
    expect(questsOf('existing_activity', 'services'), isNot(contains('q21')));
    // The other journeys never see journey C.
    expect(questsOf('vague_idea', 'trade'), isNot(contains('q16')));
    expect(questsOf('vague_idea', 'trade'), contains('q01'));
  });
}
