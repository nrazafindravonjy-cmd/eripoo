import '../../../content/content_pack.dart';
import 'answer.dart';

/// Help shown on a question after "I don't understand" / "Show an example"
/// / "Help me" (docs/PRODUCT_ARCHITECTURE.md §3.4).
class HelpState {
  const HelpState({
    this.rephraseLevel = 0,
    this.showExample = false,
    this.hintsShown = 0,
    this.notUnderstood = 0,
  });

  /// 0: none, 1: first rephrasing, 2: simpler one.
  final int rephraseLevel;
  final bool showExample;
  final int hintsShown;
  final int notUnderstood;

  /// Two "I don't understand" on the same question: offer the example
  /// directly and the possibility to skip.
  bool get stuck => notUnderstood >= 2;

  /// Level stored with the answer: 0 none, 1–2 rephrasing, 3 example,
  /// 4 hints.
  int get level => hintsShown > 0
      ? 4
      : showExample
      ? 3
      : rephraseLevel;
}

/// Going through one step, block by block. Pure: the caller stores the
/// answers (AnswerRepository) and the progress.
class StepSession {
  StepSession({
    required this.step,
    this.fastTrack = false,
    Map<String, Answer> answers = const {},
  }) : blocks = _visibleBlocks(step, fastTrack),
       _answers = Map.of(answers);

  final Step step;
  final bool fastTrack;

  /// Blocks shown, one per screen.
  final List<Block> blocks;
  final Map<String, Answer> _answers;
  final _help = <String, HelpState>{};
  var _index = 0;

  /// Fast track keeps only the deliverable (and the missions).
  static List<Block> _visibleBlocks(Step step, bool fastTrack) {
    if (!fastTrack) return step.blocks;
    final kept = step.fastTrackBlocks.isNotEmpty
        ? step.fastTrackBlocks.toSet()
        : step.outputs.map((o) => o.fromBlock).toSet();
    final visible = [
      for (final b in step.blocks)
        if (kept.contains(b.id) || b is MissionBlock) b,
    ];
    return visible.isEmpty ? step.blocks : visible;
  }

  int get index => _index;
  Block get current => blocks[_index];
  bool get isFirst => _index == 0;
  bool get isLast => _index == blocks.length - 1;
  Map<String, Answer> get answers => Map.unmodifiable(_answers);

  /// Starts at the first unanswered question (resuming a step).
  void resume() {
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      if (b is QuestionBlock && !_answers.containsKey(b.id)) {
        _index = i;
        return;
      }
    }
    _index = 0;
  }

  /// A required question must be answered (or "I don't know") to go on.
  bool get canGoNext {
    final b = current;
    return b is! QuestionBlock || b.optional || _answers.containsKey(b.id);
  }

  void next() {
    if (!isLast && canGoNext) _index++;
  }

  void back() {
    if (!isFirst) _index--;
  }

  HelpState help(String blockId) => _help[blockId] ?? const HelpState();

  /// "I don't understand": next rephrasing level; the second time, the
  /// example too.
  HelpState notUnderstood(QuestionBlock block) {
    final h = help(block.id);
    final count = h.notUnderstood + 1;
    final next = HelpState(
      rephraseLevel: count.clamp(0, block.help.rephrase.length),
      showExample: h.showExample || count >= 2,
      hintsShown: h.hintsShown,
      notUnderstood: count,
    );
    _help[block.id] = next;
    return next;
  }

  HelpState showExample(QuestionBlock block) {
    final h = help(block.id);
    return _help[block.id] = HelpState(
      rephraseLevel: h.rephraseLevel,
      showExample: true,
      hintsShown: h.hintsShown,
      notUnderstood: h.notUnderstood,
    );
  }

  /// "Help me": one more hint, up to the last one.
  HelpState nextHint(QuestionBlock block) {
    final h = help(block.id);
    return _help[block.id] = HelpState(
      rephraseLevel: h.rephraseLevel,
      showExample: h.showExample,
      hintsShown: (h.hintsShown + 1).clamp(0, block.help.hints.length),
      notUnderstood: h.notUnderstood,
    );
  }

  /// Records an answer (with the help level used) and returns it for
  /// storage. Validates it against the question.
  Answer answer(QuestionBlock block, Object? value) {
    final a = Answer(
      _typeOf(block.answer.kind),
      _validated(block, value),
      helpUsed: help(block.id).level,
    );
    _answers[block.id] = a;
    return a;
  }

  /// Open questions can be answered aloud (CLAUDE.md §25), except the
  /// project's name, which must be written.
  bool canAnswerByVoice(QuestionBlock block) =>
      block.answer.kind == AnswerKind.text &&
      !step.outputs.any(
        (o) => o.fromBlock == block.id && o.target is ProjectTitleTarget,
      );

  /// Forgets an answer (its recording was deleted): asked again.
  void clear(QuestionBlock block) => _answers.remove(block.id);

  /// A spoken answer to an open question: the encrypted recording's media
  /// id.
  Answer answerVoice(QuestionBlock block, String mediaId) {
    if (!canAnswerByVoice(block) || mediaId.isEmpty) {
      throw ArgumentError.value('(hidden)', 'mediaId', 'not an open question');
    }
    return _answers[block.id] = Answer(
      AnswerType.voice,
      mediaId,
      helpUsed: help(block.id).level,
    );
  }

  /// "I don't know": a real answer, useful information.
  Answer dontKnow(QuestionBlock block) =>
      _answers[block.id] = Answer.unknown(helpUsed: help(block.id).level);

  /// Every required question of the visible blocks is answered.
  bool get complete => blocks.whereType<QuestionBlock>().every(
    (q) => q.optional || _answers.containsKey(q.id),
  );

  static AnswerType _typeOf(AnswerKind kind) => switch (kind) {
    AnswerKind.choice => AnswerType.choice,
    AnswerKind.multiChoice => AnswerType.multiChoice,
    AnswerKind.text => AnswerType.text,
    AnswerKind.number => AnswerType.number,
    AnswerKind.money => AnswerType.money,
  };

  static Object _validated(QuestionBlock block, Object? value) {
    final spec = block.answer;
    final options = {for (final o in spec.options) o.value};
    switch (spec.kind) {
      case AnswerKind.choice:
        if (value is String && options.contains(value)) return value;
      case AnswerKind.multiChoice:
        if (value is List<String> &&
            value.isNotEmpty &&
            value.every(options.contains)) {
          return List<String>.unmodifiable(value);
        }
      case AnswerKind.text:
        if (value is String) {
          final text = value.trim();
          final max = spec.maxLength;
          if (text.isNotEmpty && (max == null || text.length <= max)) {
            return text;
          }
        }
      case AnswerKind.number:
        if (value is num && _inRange(spec, value)) return value;
      case AnswerKind.money:
        // Whole ariary only (docs/PRODUCT_ARCHITECTURE.md §10).
        if (value is int && value >= 0 && _inRange(spec, value)) return value;
    }
    throw ArgumentError.value('(hidden)', 'value', 'invalid answer');
  }

  static bool _inRange(AnswerSpec spec, num v) =>
      (spec.min == null || v >= spec.min!) &&
      (spec.max == null || v <= spec.max!);
}
