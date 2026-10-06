import 'json_reader.dart';
import 'progress_state.dart';

/// What a rule can read. Implemented over local data by the app and by
/// plain maps in tests. Facts are typed tokens, numbers or booleans: rules
/// never see free text (docs/PRODUCT_ARCHITECTURE.md §2).
abstract interface class RuleContext {
  Object? fact(String key);
  bool hasFact(String key);
  StepStatus stepStatus(String stepId);
  QuestState questState(String questId);
  MissionStatus? missionStatus(String missionId);

  /// Number of [entity] items whose fields equal [where].
  int count(String entity, Map<String, String> where);

  /// When the subject happened, or null if it did not (yet).
  DateTime? eventTime(EventSubject subject);
  DateTime get now;
}

/// Value a fact takes when the user answered "I don't know" to a choice.
const unknownFactValue = 'unknown';

/// Entities a `count` rule may count, with the fields it may filter on.
/// Counting never reads text.
const countableEntities = <String, Set<String>>{
  'steps': {'status', 'quest'},
  'quests': {'state'},
  'missions': {'status'},
  'unknown_answers': {'quest'},
};

enum EventKind { stepCompleted, missionAccepted, missionCompleted }

class EventSubject {
  const EventSubject(this.kind, this.id);
  final EventKind kind;
  final String id;
}

/// A reference from a rule to something the pack must define.
enum RefKind { fact, step, quest, mission }

class RuleRef {
  const RuleRef(this.kind, this.id);
  final RefKind kind;
  final String id;
}

/// Comparison on a number.
class NumberTest {
  const NumberTest({this.eq, this.gte, this.lte});
  final num? eq;
  final num? gte;
  final num? lte;

  static const _keys = {'eq', 'gte', 'lte'};

  factory NumberTest.read(JsonReader json) {
    final test = NumberTest(
      eq: json.has('eq') ? json['eq'].number : null,
      gte: json.has('gte') ? json['gte'].number : null,
      lte: json.has('lte') ? json['lte'].number : null,
    );
    if (test.eq == null && test.gte == null && test.lte == null) {
      json.fail('needs eq, gte or lte');
    }
    return test;
  }

  bool matches(num value) =>
      (eq == null || value == eq) &&
      (gte == null || value >= gte!) &&
      (lte == null || value <= lte!);
}

/// Deterministic rule language (docs/PRODUCT_ARCHITECTURE.md §3.2): a JSON
/// tree read by [Rule.read] and evaluated without `eval`.
sealed class Rule {
  const Rule();

  bool evaluate(RuleContext context);

  Iterable<RuleRef> get references;

  /// Parses a rule; unknown operators and malformed values are errors.
  factory Rule.read(JsonReader json) {
    if (!json.isMap) json.fail('a rule must be an object');
    final keys = json.keys;
    if (keys.contains('all')) {
      json.onlyKeys({'all'});
      return AllRule([for (final r in json['all'].list) Rule.read(r)]);
    }
    if (keys.contains('any')) {
      json.onlyKeys({'any'});
      return AnyRule([for (final r in json['any'].list) Rule.read(r)]);
    }
    if (keys.contains('not')) {
      json.onlyKeys({'not'});
      return NotRule(Rule.read(json['not']));
    }
    if (keys.contains('fact')) return FactRule.read(json);
    if (keys.contains('step')) {
      json.onlyKeys({'step', 'is'});
      return StepRule(
        json['step'].id,
        _statuses(json['is'], StepStatus.values),
      );
    }
    if (keys.contains('quest')) {
      json.onlyKeys({'quest', 'is'});
      return QuestRule(
        json['quest'].id,
        _statuses(json['is'], QuestState.values),
      );
    }
    if (keys.contains('mission')) {
      json.onlyKeys({'mission', 'is'});
      return MissionRule(
        json['mission'].id,
        _statuses(json['is'], MissionStatus.values),
      );
    }
    if (keys.contains('count')) return CountRule.read(json);
    if (keys.contains('days_since')) return DaysSinceRule.read(json);
    json.fail('unknown rule operator (${keys.join(', ')})');
  }

  static Set<T> _statuses<T extends Enum>(JsonReader json, List<T> values) =>
      json.isList
      ? {for (final v in json.list) v.oneOf(values)}
      : {json.oneOf(values)};
}

class AllRule extends Rule {
  const AllRule(this.rules);
  final List<Rule> rules;

  @override
  bool evaluate(RuleContext context) => rules.every((r) => r.evaluate(context));

  @override
  Iterable<RuleRef> get references => rules.expand((r) => r.references);
}

class AnyRule extends Rule {
  const AnyRule(this.rules);
  final List<Rule> rules;

  @override
  bool evaluate(RuleContext context) => rules.any((r) => r.evaluate(context));

  @override
  Iterable<RuleRef> get references => rules.expand((r) => r.references);
}

class NotRule extends Rule {
  const NotRule(this.rule);
  final Rule rule;

  @override
  bool evaluate(RuleContext context) => !rule.evaluate(context);

  @override
  Iterable<RuleRef> get references => rule.references;
}

/// `{fact: key, eq|ne: token|number|bool}`, `{fact, in: [...]}`,
/// `{fact, gte|lte: n}`, `{fact, exists: bool}`.
class FactRule extends Rule {
  const FactRule(
    this.key, {
    this.eq,
    this.ne,
    this.inValues,
    this.number,
    this.exists,
  });

  final String key;
  final Object? eq;
  final Object? ne;
  final Set<Object>? inValues;
  final NumberTest? number;
  final bool? exists;

  factory FactRule.read(JsonReader json) {
    json.onlyKeys({'fact', 'eq', 'ne', 'in', 'gte', 'lte', 'exists'});
    final key = json['fact'].id;
    if (!key.contains('.')) json['fact'].fail('a fact key has a namespace');
    Object scalar(JsonReader v) {
      final value = v.value;
      if (value is bool || value is num) return value!;
      return v.token;
    }

    final hasNumber = json.has('gte') || json.has('lte');
    final rule = FactRule(
      key,
      eq: json.has('eq') ? scalar(json['eq']) : null,
      ne: json.has('ne') ? scalar(json['ne']) : null,
      inValues: json.has('in')
          ? {for (final v in json['in'].list) scalar(v)}
          : null,
      number: hasNumber
          ? NumberTest(
              gte: json.has('gte') ? json['gte'].number : null,
              lte: json.has('lte') ? json['lte'].number : null,
            )
          : null,
      exists: json.has('exists') ? json['exists'].boolean : null,
    );
    final tests = [
      rule.eq,
      rule.ne,
      rule.inValues,
      rule.number,
      rule.exists,
    ].where((t) => t != null).length;
    if (tests != 1) json.fail('a fact rule needs exactly one test');
    return rule;
  }

  @override
  bool evaluate(RuleContext context) {
    if (exists != null) return context.hasFact(key) == exists;
    if (!context.hasFact(key)) return ne != null;
    final value = context.fact(key);
    if (eq != null) return value == eq;
    if (ne != null) return value != ne;
    if (inValues != null) return inValues!.contains(value);
    return value is num && number!.matches(value);
  }

  @override
  Iterable<RuleRef> get references => [RuleRef(RefKind.fact, key)];
}

class StepRule extends Rule {
  const StepRule(this.stepId, this.statuses);
  final String stepId;
  final Set<StepStatus> statuses;

  @override
  bool evaluate(RuleContext context) =>
      statuses.contains(context.stepStatus(stepId));

  @override
  Iterable<RuleRef> get references => [RuleRef(RefKind.step, stepId)];
}

class QuestRule extends Rule {
  const QuestRule(this.questId, this.states);
  final String questId;
  final Set<QuestState> states;

  @override
  bool evaluate(RuleContext context) =>
      states.contains(context.questState(questId));

  @override
  Iterable<RuleRef> get references => [RuleRef(RefKind.quest, questId)];
}

class MissionRule extends Rule {
  const MissionRule(this.missionId, this.statuses);
  final String missionId;
  final Set<MissionStatus> statuses;

  @override
  bool evaluate(RuleContext context) {
    final status = context.missionStatus(missionId);
    return status != null && statuses.contains(status);
  }

  @override
  Iterable<RuleRef> get references => [RuleRef(RefKind.mission, missionId)];
}

/// `{count: missions, where: {status: completed}, gte: 2}`.
class CountRule extends Rule {
  const CountRule(this.entity, this.where, this.test);
  final String entity;
  final Map<String, String> where;
  final NumberTest test;

  factory CountRule.read(JsonReader json) {
    json.onlyKeys({'count', 'where', ...NumberTest._keys});
    final entity = json['count'].id;
    final fields = countableEntities[entity];
    if (fields == null) json['count'].fail('cannot count "$entity"');
    final where = <String, String>{};
    if (json.has('where')) {
      final w = json['where'];
      w.onlyKeys(fields);
      for (final key in w.keys) {
        where[key] = w[key].token;
      }
    }
    return CountRule(entity, where, NumberTest.read(json));
  }

  @override
  bool evaluate(RuleContext context) =>
      test.matches(context.count(entity, where));

  @override
  Iterable<RuleRef> get references => const [];
}

/// `{days_since: {step_completed: q01.s02}, gte: 3}`. False while the event
/// has not happened.
class DaysSinceRule extends Rule {
  const DaysSinceRule(this.subject, this.test);
  final EventSubject subject;
  final NumberTest test;

  factory DaysSinceRule.read(JsonReader json) {
    json.onlyKeys({'days_since', ...NumberTest._keys});
    final s = json['days_since'];
    s.onlyKeys({'step_completed', 'mission_accepted', 'mission_completed'});
    if (s.keys.length != 1) s.fail('exactly one event');
    final key = s.keys.single;
    final kind = switch (key) {
      'step_completed' => EventKind.stepCompleted,
      'mission_accepted' => EventKind.missionAccepted,
      _ => EventKind.missionCompleted,
    };
    return DaysSinceRule(EventSubject(kind, s[key].id), NumberTest.read(json));
  }

  @override
  bool evaluate(RuleContext context) {
    final at = context.eventTime(subject);
    if (at == null) return false;
    return test.matches(context.now.difference(at).inDays);
  }

  @override
  Iterable<RuleRef> get references => [
    RuleRef(
      subject.kind == EventKind.stepCompleted ? RefKind.step : RefKind.mission,
      subject.id,
    ),
  ];
}
