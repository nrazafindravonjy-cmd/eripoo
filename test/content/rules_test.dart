import 'package:eripoo/content/json_reader.dart';
import 'package:eripoo/content/progress_state.dart';
import 'package:eripoo/content/rules.dart';
import 'package:flutter_test/flutter_test.dart';

class MapContext implements RuleContext {
  MapContext({
    this.facts = const {},
    this.steps = const {},
    this.counts = const {},
    this.events = const {},
  });

  final Map<String, Object?> facts;
  final Map<String, StepStatus> steps;
  final Map<String, int> counts;
  final Map<String, DateTime> events;

  @override
  final DateTime now = DateTime.utc(2026, 10, 6);

  @override
  Object? fact(String key) => facts[key];
  @override
  bool hasFact(String key) => facts[key] != null;
  @override
  StepStatus stepStatus(String stepId) => steps[stepId] ?? StepStatus.available;
  @override
  QuestState questState(String questId) => QuestState.notStarted;
  @override
  MissionStatus? missionStatus(String missionId) => null;
  @override
  int count(String entity, Map<String, String> where) =>
      counts['$entity:${where.values.join(',')}'] ?? 0;
  @override
  DateTime? eventTime(EventSubject subject) => events[subject.id];
}

bool eval(Map<String, Object?> rule, MapContext context) =>
    Rule.read(JsonReader(rule)).evaluate(context);

void main() {
  final ctx = MapContext(
    facts: {'diag.stage': 'vague_idea', 'diag.hours': 4, 'diag.paid': false},
    steps: {'q01.s01': StepStatus.completed},
    counts: {'missions:completed': 2},
    events: {'q01.s01': DateTime.utc(2026, 10, 1)},
  );

  test('fact comparisons', () {
    expect(eval({'fact': 'diag.stage', 'eq': 'vague_idea'}, ctx), isTrue);
    expect(
      eval({
        'fact': 'diag.stage',
        'in': ['no_idea'],
      }, ctx),
      isFalse,
    );
    expect(eval({'fact': 'diag.hours', 'gte': 3}, ctx), isTrue);
    expect(eval({'fact': 'diag.hours', 'lte': 3}, ctx), isFalse);
    expect(eval({'fact': 'diag.paid', 'eq': false}, ctx), isTrue);
    expect(eval({'fact': 'diag.mood', 'exists': false}, ctx), isTrue);
    // A missing fact equals nothing but differs from everything.
    expect(eval({'fact': 'diag.mood', 'eq': 'happy'}, ctx), isFalse);
    expect(eval({'fact': 'diag.mood', 'ne': 'happy'}, ctx), isTrue);
  });

  test('combinators, steps, counts and days since', () {
    expect(
      eval({
        'all': [
          {
            'step': 'q01.s01',
            'is': ['completed', 'fast_tracked'],
          },
          {
            'not': {'fact': 'diag.stage', 'eq': 'no_idea'},
          },
          {
            'any': [
              {
                'count': 'missions',
                'where': {'status': 'completed'},
                'gte': 2,
              },
              {'fact': 'diag.hours', 'gte': 40},
            ],
          },
          {
            'days_since': {'step_completed': 'q01.s01'},
            'gte': 5,
          },
        ],
      }, ctx),
      isTrue,
    );
    expect(
      eval({
        'days_since': {'step_completed': 'q09.s01'},
        'gte': 0,
      }, ctx),
      isFalse,
      reason: 'an event that did not happen',
    );
  });

  test('malformed rules are refused', () {
    for (final bad in <Map<String, Object?>>[
      {'eval': 'x'},
      {'fact': 'nonamespace', 'eq': 'a'},
      {
        'fact': 'diag.x',
        'eq': 'a',
        'in': ['b'],
      },
      {'fact': 'diag.x', 'eq': 'Free text!'},
      {'count': 'hypotheses_text', 'gte': 1},
      {
        'count': 'missions',
        'where': {'title': 'x'},
        'gte': 1,
      },
      {'count': 'missions'},
      {'step': 'q01.s01', 'is': 'finished'},
      {
        'days_since': {'step_completed': 'q01.s01', 'mission_accepted': 'm.x'},
        'gte': 1,
      },
    ]) {
      expect(
        () => Rule.read(JsonReader(bad)),
        throwsA(isA<ContentFormatException>()),
        reason: '$bad',
      );
    }
  });

  test('references are reported for the validator', () {
    final rule = Rule.read(
      JsonReader({
        'all': [
          {'fact': 'diag.stage', 'eq': 'a'},
          {'step': 'q01.s01', 'is': 'completed'},
          {'mission': 'm.x', 'is': 'completed'},
          {'quest': 'q02', 'is': 'completed'},
        ],
      }),
    );
    expect(rule.references.map((r) => '${r.kind.name}:${r.id}'), [
      'fact:diag.stage',
      'step:q01.s01',
      'mission:m.x',
      'quest:q02',
    ]);
  });
}
