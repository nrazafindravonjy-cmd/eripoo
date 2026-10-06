import 'dart:convert';

import 'package:eripoo/content/content_pack.dart';
import 'package:eripoo/content/content_validator.dart';
import 'package:eripoo/content/planner.dart';
import 'package:eripoo/content/progress_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixture_pack.dart';

final now = DateTime.utc(2026, 10, 6, 12);
final pack = ContentPack.parse(jsonEncode(fixturePack()));

JourneyPlan planWith({
  Map<String, Object?> facts = const {},
  Map<String, StepRecord> steps = const {},
  Map<String, MissionRecord> missions = const {},
  DateTime? at,
}) => plan(
  PlannerInput(
    pack: pack,
    now: at ?? now,
    facts: facts,
    steps: steps,
    missions: missions,
  ),
);

const done = StepRecord(StepStatus.completed);
const diagDone = {'diag.s01': done};

StepStatus statusOf(JourneyPlan p, String id) => p.step(id)!.status;

void main() {
  test('first launch: the diagnostic comes first', () {
    final p = planWith();
    expect(p.diagnosticDone, isFalse);
    expect(p.next!.step.id, 'diag.s01');
  });

  test('after the diagnostic: first step available, the rest locked', () {
    final p = planWith(steps: diagDone);
    expect(p.diagnosticDone, isTrue);
    expect(statusOf(p, 'q01.s01'), StepStatus.available);
    expect(statusOf(p, 'q01.s02'), StepStatus.locked);
    expect(p.step('q01.s02')!.lockReason, LockReason.previousStep);
    expect(statusOf(p, 'q02.s01'), StepStatus.locked);
    expect(p.step('q02.s01')!.lockReason, LockReason.questLocked);
    expect(p.next!.step.id, 'q01.s01');
    expect(p.quests.first.done, 0);
    expect(p.quests.first.total, 3);
  });

  test('progress unlocks the next step and a step in progress comes first', () {
    final p = planWith(
      steps: {
        ...diagDone,
        'q01.s01': done,
        'q01.s02': const StepRecord(StepStatus.inProgress),
      },
    );
    expect(statusOf(p, 'q01.s02'), StepStatus.inProgress);
    expect(p.next!.step.id, 'q01.s02');
    expect(p.quests.first.done, 1);
  });

  test('a skipped step does not block the next one, and resurfaces later', () {
    final until = now.add(const Duration(days: 3));
    final steps = {
      ...diagDone,
      'q01.s01': done,
      'q01.s02': StepRecord(StepStatus.deferred, deferredUntil: until),
    };
    final p = planWith(steps: steps);
    expect(statusOf(p, 'q01.s02'), StepStatus.deferred);
    expect(statusOf(p, 'q01.s03'), StepStatus.available);
    expect(p.next!.step.id, 'q01.s03');

    final later = planWith(steps: steps, at: until);
    expect(statusOf(later, 'q01.s02'), StepStatus.available);
    expect(later.step('q01.s02')!.resurfaced, isTrue);
  });

  test('postponed steps are recommended only when nothing else is left', () {
    final p = planWith(
      steps: {
        ...diagDone,
        'q01.s01': done,
        'q01.s02': const StepRecord(StepStatus.postponed),
        'q01.s03': done,
      },
    );
    expect(statusOf(p, 'q01.s02'), StepStatus.postponed);
    expect(p.next!.step.id, 'q01.s02');
  });

  test('completing a quest unlocks the next quest (rule)', () {
    final p = planWith(
      steps: {...diagDone, 'q01.s01': done, 'q01.s02': done, 'q01.s03': done},
    );
    expect(p.quests.first.state.name, 'completed');
    expect(statusOf(p, 'q02.s01'), StepStatus.available);
    expect(p.next!.step.id, 'q02.s01');
  });

  test('advanced profile: learning skipped (readable), deliverables asked', () {
    final p = planWith(
      facts: {'diag.idea_stage': 'existing_activity'},
      steps: diagDone,
    );
    final learn = p.step('q01.s01')!;
    expect(learn.status, StepStatus.fastTracked);
    expect(learn.fastTrack, isTrue);
    // The deliverable step is not skipped, only shortened.
    final reflect = p.step('q01.s02')!;
    expect(reflect.status, StepStatus.available);
    expect(reflect.fastTrack, isTrue);
    expect(p.next!.step.id, 'q01.s02');
    // The mission step is never skipped silently.
    expect(p.step('q01.s03')!.status, StepStatus.locked);
  });

  test('stored progress is never undone by a rule change', () {
    final p = planWith(steps: {...diagDone, 'q02.s01': done});
    expect(statusOf(p, 'q02.s01'), StepStatus.completed);
  });

  test('the same input gives the same plan (no hidden clock or state)', () {
    final a = planWith(steps: diagDone);
    final b = planWith(steps: diagDone);
    expect(
      [
        for (final q in a.quests)
          for (final s in q.steps) s.status,
      ],
      [
        for (final q in b.quests)
          for (final s in q.steps) s.status,
      ],
    );
  });

  test('rules on missions and counts', () {
    final p = planWith(
      steps: {...diagDone, 'q01.s01': done, 'q01.s02': done},
      missions: {
        'm.observe': MissionRecord(
          MissionStatus.completed,
          acceptedAt: now.subtract(const Duration(days: 4)),
          completedAt: now,
        ),
      },
    );
    expect(statusOf(p, 'q01.s03'), StepStatus.available);
  });

  test('a rule testing "locked" is refused by the validator', () {
    final json = fixturePack();
    ((json['quests']! as List<Object?>)[2]!
        as Map<String, Object?>)['available_when'] = {
      'step': 'q01.s01',
      'is': 'locked',
    };
    final report = validatePack(ContentPack.parse(jsonEncode(json)));
    expect(report.errors, contains(contains('cannot test locked')));
  });
}
