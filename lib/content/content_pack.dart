import 'dart:convert';

import 'json_reader.dart';
import 'localized_text.dart';
import 'rules.dart';

/// Format of the pack JSON understood by this app version.
const supportedPackFormat = 1;

/// Block types this app can render. A pack using another type needs a
/// newer app (docs/ARCHITECTURE.md §6).
enum BlockType { text, example, tip, term, question, synthesis, mission }

enum StepType { learn, reflect, act, checkpoint, tool }

/// The diagnostic is content too, run before the journey.
enum QuestKind { diagnostic, journey }

/// Kinds of answers a question accepts. Free text never becomes a fact.
enum AnswerKind { choice, multiChoice, text, number, money }

/// Project sections that steps may fill (docs/PRODUCT_ARCHITECTURE.md §7).
const projectSections = {
  'vision',
  'problem',
  'customers',
  'solution',
  'offer',
  'market',
  'competition',
  'business_model',
  'pricing',
  'finances',
  'marketing',
  'launch',
  'formalization',
  'pitch',
};

const maturityStages = {
  'exploration',
  'validation',
  'construction',
  'preparation',
  'launch',
};

sealed class Block {
  const Block(this.id);
  final String id;
  BlockType get type;

  factory Block.read(JsonReader json) {
    final type = json['type'].oneOf(BlockType.values);
    final id = json['id'].id;
    return switch (type) {
      BlockType.text => TextBlock.read(id, json),
      BlockType.example => ExampleBlock.read(id, json),
      BlockType.tip => TipBlock.read(id, json),
      BlockType.term => TermBlock.read(id, json),
      BlockType.question => QuestionBlock.read(id, json),
      BlockType.synthesis => SynthesisBlock.read(id, json),
      BlockType.mission => MissionBlock.read(id, json),
    };
  }
}

class TextBlock extends Block {
  const TextBlock(super.id, this.body);
  final LocalizedText body;
  @override
  BlockType get type => BlockType.text;

  factory TextBlock.read(String id, JsonReader json) {
    json.onlyKeys({'id', 'type', 'body'});
    return TextBlock(id, LocalizedText.read(json['body']));
  }
}

/// A concrete example from the Malagasy context.
class ExampleBlock extends Block {
  const ExampleBlock(super.id, this.body);
  final LocalizedText body;
  @override
  BlockType get type => BlockType.example;

  factory ExampleBlock.read(String id, JsonReader json) {
    json.onlyKeys({'id', 'type', 'body'});
    return ExampleBlock(id, LocalizedText.read(json['body']));
  }
}

class TipBlock extends Block {
  const TipBlock(super.id, this.body);
  final LocalizedText body;
  @override
  BlockType get type => BlockType.tip;

  factory TipBlock.read(String id, JsonReader json) {
    json.onlyKeys({'id', 'type', 'body'});
    return TipBlock(id, LocalizedText.read(json['body']));
  }
}

/// Plain words first, then the entrepreneurial term.
class TermBlock extends Block {
  const TermBlock(super.id, this.plain, this.term, this.definition);
  final LocalizedText plain;
  final LocalizedText term;
  final LocalizedText definition;
  @override
  BlockType get type => BlockType.term;

  factory TermBlock.read(String id, JsonReader json) {
    json.onlyKeys({'id', 'type', 'plain', 'term', 'definition'});
    return TermBlock(
      id,
      LocalizedText.read(json['plain']),
      LocalizedText.read(json['term']),
      LocalizedText.read(json['definition']),
    );
  }
}

class ChoiceOption {
  const ChoiceOption(this.value, this.label);
  final String value;
  final LocalizedText label;
}

class AnswerSpec {
  const AnswerSpec({
    required this.kind,
    this.options = const [],
    this.maxLength,
    this.min,
    this.max,
  });

  final AnswerKind kind;
  final List<ChoiceOption> options;
  final int? maxLength;
  final num? min;
  final num? max;

  bool get isChoice =>
      kind == AnswerKind.choice || kind == AnswerKind.multiChoice;

  factory AnswerSpec.read(JsonReader json) {
    json.onlyKeys({'kind', 'options', 'max_length', 'min', 'max'});
    final kind = json['kind'].oneOf(AnswerKind.values);
    final options = [
      for (final o in json['options'].listOrEmpty)
        () {
          o.onlyKeys({'value', 'label'});
          return ChoiceOption(o['value'].token, LocalizedText.read(o['label']));
        }(),
    ];
    final spec = AnswerSpec(
      kind: kind,
      options: options,
      maxLength: json['max_length'].intOrNull,
      min: json.has('min') ? json['min'].number : null,
      max: json.has('max') ? json['max'].number : null,
    );
    if (spec.isChoice && options.length < 2) {
      json['options'].fail('a choice needs at least 2 options');
    }
    if (!spec.isChoice && options.isNotEmpty) {
      json['options'].fail('options only for choices');
    }
    final values = options.map((o) => o.value).toList();
    if (values.toSet().length != values.length) {
      json['options'].fail('duplicate option value');
    }
    return spec;
  }
}

/// Anti-blocking help every question must declare
/// (docs/PRODUCT_ARCHITECTURE.md §3.4).
class QuestionHelp {
  const QuestionHelp({
    required this.rephrase,
    required this.example,
    required this.hints,
  });

  /// Level 1, then level 2 (simpler, with a concrete example).
  final List<LocalizedText> rephrase;
  final LocalizedText example;
  final List<LocalizedText> hints;

  factory QuestionHelp.read(JsonReader json) {
    json.onlyKeys({'rephrase', 'example', 'hints'});
    final help = QuestionHelp(
      rephrase: [for (final r in json['rephrase'].list) LocalizedText.read(r)],
      example: LocalizedText.read(json['example']),
      hints: [for (final h in json['hints'].list) LocalizedText.read(h)],
    );
    if (help.rephrase.isEmpty || help.rephrase.length > 2) {
      json['rephrase'].fail('1 or 2 rephrasing levels');
    }
    if (help.hints.isEmpty) json['hints'].fail('at least one hint');
    return help;
  }
}

class QuestionBlock extends Block {
  const QuestionBlock(
    super.id, {
    required this.prompt,
    required this.answer,
    required this.help,
    this.optional = false,
  });

  final LocalizedText prompt;
  final AnswerSpec answer;
  final QuestionHelp help;
  final bool optional;

  @override
  BlockType get type => BlockType.question;

  factory QuestionBlock.read(String id, JsonReader json) {
    json.onlyKeys({'id', 'type', 'prompt', 'answer', 'help', 'optional'});
    return QuestionBlock(
      id,
      prompt: LocalizedText.read(json['prompt']),
      answer: AnswerSpec.read(json['answer']),
      help: QuestionHelp.read(json['help']),
      optional: json['optional'].boolOr(false),
    );
  }
}

/// Shows back what the user built in this step.
class SynthesisBlock extends Block {
  const SynthesisBlock(super.id, this.intro, this.shows);
  final LocalizedText intro;
  final List<String> shows;
  @override
  BlockType get type => BlockType.synthesis;

  factory SynthesisBlock.read(String id, JsonReader json) {
    json.onlyKeys({'id', 'type', 'intro', 'shows'});
    return SynthesisBlock(id, LocalizedText.read(json['intro']), [
      for (final s in json['shows'].list) s.id,
    ]);
  }
}

/// Proposes a mission (a real-world action).
class MissionBlock extends Block {
  const MissionBlock(super.id, this.missionId);
  final String missionId;
  @override
  BlockType get type => BlockType.mission;

  factory MissionBlock.read(String id, JsonReader json) {
    json.onlyKeys({'id', 'type', 'mission'});
    return MissionBlock(id, json['mission'].id);
  }
}

sealed class OutputTarget {
  const OutputTarget();
}

/// Writes the answer as a fact (choices and numbers only).
class FactTarget extends OutputTarget {
  const FactTarget(this.key);
  final String key;
}

/// Writes the answer into a project section field.
class SectionTarget extends OutputTarget {
  const SectionTarget(this.section, this.field, {this.tracked = false});
  final String section;
  final String field;
  final bool tracked;
}

/// Creates the project, titled with the answer (diagnostic).
class ProjectTitleTarget extends OutputTarget {
  const ProjectTitleTarget();
}

class StepOutput {
  const StepOutput(this.fromBlock, this.target);
  final String fromBlock;
  final OutputTarget target;

  factory StepOutput.read(JsonReader json) {
    json.onlyKeys({
      'from',
      'fact',
      'section',
      'field',
      'tracked',
      'project_title',
    });
    final from = json['from'].id;
    if (json.has('fact')) {
      return StepOutput(from, FactTarget(json['fact'].id));
    }
    if (json.has('section')) {
      final section = json['section'].token;
      if (!projectSections.contains(section)) {
        json['section'].fail('unknown section "$section"');
      }
      return StepOutput(
        from,
        SectionTarget(
          section,
          json['field'].token,
          tracked: json['tracked'].boolOr(false),
        ),
      );
    }
    if (json['project_title'].boolOr(false)) {
      return StepOutput(from, const ProjectTitleTarget());
    }
    json.fail('an output needs fact, section or project_title');
  }
}

class Step {
  const Step({
    required this.id,
    required this.type,
    required this.title,
    required this.blocks,
    this.availableWhen,
    this.completeWhen,
    this.fastTrackWhen,
    this.fastTrackBlocks = const [],
    this.outputs = const [],
    this.deferDays = 3,
  });

  final String id;
  final StepType type;
  final LocalizedText title;
  final List<Block> blocks;

  /// Default: the previous step of the quest is done.
  final Rule? availableWhen;

  /// Extra condition on top of answering the required questions.
  final Rule? completeWhen;

  /// Advanced profile: only [fastTrackBlocks] (the deliverable) are asked.
  final Rule? fastTrackWhen;
  final List<String> fastTrackBlocks;
  final List<StepOutput> outputs;

  /// "Skip for now": the step comes back after this many days.
  final int deferDays;

  Iterable<QuestionBlock> get questions => blocks.whereType<QuestionBlock>();
  Iterable<String> get missionIds =>
      blocks.whereType<MissionBlock>().map((b) => b.missionId);

  Block? block(String blockId) {
    for (final b in blocks) {
      if (b.id == blockId) return b;
    }
    return null;
  }

  factory Step.read(JsonReader json) {
    json.onlyKeys({
      'id',
      'type',
      'title',
      'blocks',
      'available_when',
      'complete_when',
      'fast_track_when',
      'fast_track_blocks',
      'outputs',
      'defer_days',
    });
    Rule? rule(String key) => json.has(key) ? Rule.read(json[key]) : null;
    final step = Step(
      id: json['id'].id,
      type: json['type'].oneOf(StepType.values),
      title: LocalizedText.read(json['title']),
      blocks: [for (final b in json['blocks'].list) Block.read(b)],
      availableWhen: rule('available_when'),
      completeWhen: rule('complete_when'),
      fastTrackWhen: rule('fast_track_when'),
      fastTrackBlocks: [
        for (final b in json['fast_track_blocks'].listOrEmpty) b.id,
      ],
      outputs: [
        for (final o in json['outputs'].listOrEmpty) StepOutput.read(o),
      ],
      deferDays: json['defer_days'].intOrNull ?? 3,
    );
    if (step.blocks.isEmpty) json['blocks'].fail('a step needs blocks');
    return step;
  }
}

class Quest {
  const Quest({
    required this.id,
    required this.kind,
    required this.order,
    required this.maturity,
    required this.title,
    required this.summary,
    required this.steps,
    this.priority = 0,
    this.availableWhen,
    this.fastTrackWhen,
  });

  final String id;
  final QuestKind kind;
  final int order;
  final String maturity;
  final LocalizedText title;
  final LocalizedText summary;
  final List<Step> steps;

  /// Higher first when several quests are available.
  final int priority;
  final Rule? availableWhen;

  /// Applies to every step without its own `fast_track_when`.
  final Rule? fastTrackWhen;

  factory Quest.read(JsonReader json) {
    json.onlyKeys({
      'id',
      'kind',
      'order',
      'maturity',
      'title',
      'summary',
      'steps',
      'priority',
      'available_when',
      'fast_track_when',
    });
    final maturity = json['maturity'].token;
    if (!maturityStages.contains(maturity)) {
      json['maturity'].fail('unknown maturity stage');
    }
    final quest = Quest(
      id: json['id'].id,
      kind: json.has('kind')
          ? json['kind'].oneOf(QuestKind.values)
          : QuestKind.journey,
      order: json['order'].integer,
      maturity: maturity,
      title: LocalizedText.read(json['title']),
      summary: LocalizedText.read(json['summary']),
      steps: [for (final s in json['steps'].list) Step.read(s)],
      priority: json['priority'].intOrNull ?? 0,
      availableWhen: json.has('available_when')
          ? Rule.read(json['available_when'])
          : null,
      fastTrackWhen: json.has('fast_track_when')
          ? Rule.read(json['fast_track_when'])
          : null,
    );
    if (quest.steps.isEmpty) json['steps'].fail('a quest needs steps');
    return quest;
  }
}

class MissionTemplate {
  const MissionTemplate({
    required this.id,
    required this.title,
    required this.objective,
    required this.instructions,
    required this.deliverable,
    required this.durationMinutes,
    required this.difficulty,
    this.example,
    this.realWorld = true,
    this.completeWhen,
  });

  final String id;
  final LocalizedText title;
  final LocalizedText objective;
  final List<LocalizedText> instructions;

  /// What the user brings back (shown as the reflection prompt).
  final LocalizedText deliverable;
  final int durationMinutes;

  /// 1 (easy) to 3.
  final int difficulty;
  final LocalizedText? example;
  final bool realWorld;

  /// Extra completion condition on top of the submitted reflection.
  final Rule? completeWhen;

  factory MissionTemplate.read(JsonReader json) {
    json.onlyKeys({
      'id',
      'title',
      'objective',
      'instructions',
      'deliverable',
      'duration_minutes',
      'difficulty',
      'example',
      'real_world',
      'complete_when',
    });
    final difficulty = json['difficulty'].integer;
    if (difficulty < 1 || difficulty > 3) {
      json['difficulty'].fail('difficulty is 1, 2 or 3');
    }
    return MissionTemplate(
      id: json['id'].id,
      title: LocalizedText.read(json['title']),
      objective: LocalizedText.read(json['objective']),
      instructions: [
        for (final i in json['instructions'].list) LocalizedText.read(i),
      ],
      deliverable: LocalizedText.read(json['deliverable']),
      durationMinutes: json['duration_minutes'].integer,
      difficulty: difficulty,
      example: json.has('example') ? LocalizedText.read(json['example']) : null,
      realWorld: json['real_world'].boolOr(true),
      completeWhen: json.has('complete_when')
          ? Rule.read(json['complete_when'])
          : null,
    );
  }
}

/// A versioned content pack (docs/PRODUCT_ARCHITECTURE.md §6).
/// A field of a project section, as shown to the user.
class SectionField {
  const SectionField({
    required this.key,
    required this.label,
    this.maxLength = 1000,
  });

  final String key;
  final LocalizedText label;
  final int maxLength;

  factory SectionField.read(JsonReader json) {
    json.onlyKeys({'key', 'label', 'max_length'});
    return SectionField(
      key: json['key'].token,
      label: LocalizedText.read(json['label']),
      maxLength: json['max_length'].intOrNull ?? 1000,
    );
  }
}

/// The schema of a project section (docs/PRODUCT_ARCHITECTURE.md §7):
/// its title and fields come from content, not from code.
class SectionSchema {
  const SectionSchema({
    required this.key,
    required this.title,
    required this.fields,
    this.tool,
  });

  final String key;
  final LocalizedText title;
  final List<SectionField> fields;

  /// The tool that brings this section: it appears once the tool is
  /// unlocked (or as soon as it holds something), so the project grows
  /// with the work instead of showing empty boxes (CLAUDE.md §16).
  final String? tool;

  SectionField? field(String key) {
    for (final f in fields) {
      if (f.key == key) return f;
    }
    return null;
  }

  factory SectionSchema.read(JsonReader json) {
    json.onlyKeys({'key', 'title', 'fields', 'tool'});
    final key = json['key'].token;
    if (!projectSections.contains(key)) {
      json['key'].fail('unknown section "$key"');
    }
    return SectionSchema(
      key: key,
      title: LocalizedText.read(json['title']),
      fields: [for (final f in json['fields'].list) SectionField.read(f)],
      tool: json.has('tool') ? json['tool'].id : null,
    );
  }
}

/// The tools of the Tools tab (CLAUDE.md §20), in the order of the spec.
/// The app knows how to open some of them ([implementedTools]); the others
/// are announced, never imitated.
enum ToolKind {
  observationJournal,
  interviewGuide,
  hypotheses,
  experiments,
  competitorAnalysis,
  businessModelCanvas,
  priceCalculator,
  marginCalculator,
  breakEvenCalculator,
  marketingPlan,
  businessPlan,
  pitch,
  pitchDeck,
  adminPreparation,
}

/// Tools this version of the app can open.
const implementedTools = {
  ToolKind.observationJournal,
  ToolKind.interviewGuide,
  ToolKind.hypotheses,
  ToolKind.experiments,
  ToolKind.competitorAnalysis,
  ToolKind.priceCalculator,
  ToolKind.marginCalculator,
  ToolKind.breakEvenCalculator,
  ToolKind.businessModelCanvas,
  ToolKind.marketingPlan,
  ToolKind.businessPlan,
  ToolKind.pitch,
  ToolKind.pitchDeck,
};

/// A titled list of advice inside a tool (e.g. the interview guide).
class GuideSection {
  const GuideSection({required this.title, required this.items});

  final LocalizedText title;
  final List<LocalizedText> items;

  factory GuideSection.read(JsonReader json) {
    json.onlyKeys({'title', 'items'});
    return GuideSection(
      title: LocalizedText.read(json['title']),
      items: [for (final i in json['items'].list) LocalizedText.read(i)],
    );
  }
}

/// A tool as content defines it (docs/PRODUCT_ARCHITECTURE.md §8): what it
/// is for, its help (always readable), and the rule that unlocks it.
class ToolDefinition {
  const ToolDefinition({
    required this.id,
    required this.kind,
    required this.title,
    required this.summary,
    required this.help,
    this.unlock,
    this.unlockHint,
    this.guide = const [],
  });

  final String id;
  final ToolKind kind;
  final LocalizedText title;
  final LocalizedText summary;

  /// How to use it, readable even before it is unlocked.
  final List<LocalizedText> help;

  /// Null: available from the start.
  final Rule? unlock;

  /// "Unlocked when you…", in plain words.
  final LocalizedText? unlockHint;
  final List<GuideSection> guide;

  bool get implemented => implementedTools.contains(kind);

  factory ToolDefinition.read(JsonReader json) {
    json.onlyKeys({
      'id',
      'kind',
      'title',
      'summary',
      'help',
      'unlock',
      'unlock_hint',
      'guide',
    });
    return ToolDefinition(
      id: json['id'].id,
      kind: json['kind'].oneOf(ToolKind.values),
      title: LocalizedText.read(json['title']),
      summary: LocalizedText.read(json['summary']),
      help: [for (final h in json['help'].list) LocalizedText.read(h)],
      unlock: json.has('unlock') ? Rule.read(json['unlock']) : null,
      unlockHint: json.has('unlock_hint')
          ? LocalizedText.read(json['unlock_hint'])
          : null,
      guide: [for (final g in json['guide'].listOrEmpty) GuideSection.read(g)],
    );
  }
}

class ContentPack {
  ContentPack({
    required this.packId,
    required this.version,
    required this.minAppVersion,
    required this.blockTypes,
    required this.quests,
    required this.missions,
    this.sections = const [],
    this.tools = const [],
    this.financingGuide = const [],
  }) {
    for (final quest in quests) {
      for (final step in quest.steps) {
        _steps[step.id] = step;
        _questOfStep[step.id] = quest;
      }
      _quests[quest.id] = quest;
    }
    for (final mission in missions) {
      _missions[mission.id] = mission;
    }
  }

  final String packId;
  final String version;
  final int minAppVersion;
  final Set<BlockType> blockTypes;
  final List<Quest> quests;
  final List<MissionTemplate> missions;

  /// Project sections in display order.
  final List<SectionSchema> sections;

  /// Tools in display order.
  final List<ToolDefinition> tools;

  /// How to find money (CLAUDE.md §49): kinds of sources only.
  final List<GuideSection> financingGuide;

  ToolDefinition? tool(String id) {
    for (final t in tools) {
      if (t.id == id) return t;
    }
    return null;
  }

  SectionSchema? section(String key) {
    for (final s in sections) {
      if (s.key == key) return s;
    }
    return null;
  }

  final _steps = <String, Step>{};
  final _questOfStep = <String, Quest>{};
  final _quests = <String, Quest>{};
  final _missions = <String, MissionTemplate>{};

  Step? step(String id) => _steps[id];
  Quest? questOfStep(String stepId) => _questOfStep[stepId];
  Quest? quest(String id) => _quests[id];
  MissionTemplate? mission(String id) => _missions[id];
  Iterable<Step> get steps => _steps.values;

  /// Journey quests in display order (the diagnostic excluded).
  List<Quest> get journey =>
      quests.where((q) => q.kind == QuestKind.journey).toList()
        ..sort((a, b) => a.order.compareTo(b.order));

  Quest? get diagnostic {
    for (final q in quests) {
      if (q.kind == QuestKind.diagnostic) return q;
    }
    return null;
  }

  static ContentPack parse(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const ContentFormatException(r'$', 'not valid JSON');
    }
    return read(JsonReader(decoded));
  }

  static ContentPack read(JsonReader json) {
    json.onlyKeys({
      'format',
      'pack_id',
      'version',
      'min_app_version',
      'block_types',
      'quests',
      'missions',
      'sections',
      'tools',
      'financing_guide',
    });
    if (json['format'].integer != supportedPackFormat) {
      json['format'].fail('unsupported pack format');
    }
    return ContentPack(
      packId: json['pack_id'].id,
      version: json['version'].string,
      minAppVersion: json['min_app_version'].integer,
      blockTypes: {
        for (final t in json['block_types'].list) t.oneOf(BlockType.values),
      },
      quests: [for (final q in json['quests'].list) Quest.read(q)],
      missions: [
        for (final m in json['missions'].listOrEmpty) MissionTemplate.read(m),
      ],
      sections: [
        for (final s in json['sections'].listOrEmpty) SectionSchema.read(s),
      ],
      tools: [
        for (final t in json['tools'].listOrEmpty) ToolDefinition.read(t),
      ],
      financingGuide: [
        for (final g in json['financing_guide'].listOrEmpty)
          GuideSection.read(g),
      ],
    );
  }
}
