/// Type of a stored answer (docs/DATA_MODEL.md `answers`).
enum AnswerType { text, choice, multiChoice, number, money, unknown }

/// The user's answer to one question block. [value] is a `String` (text,
/// choice token), `List<String>` (multi choice), `num` (number) or `int`
/// (money, whole ariary); null for "I don't know".
class Answer {
  const Answer(this.type, this.value, {this.helpUsed = 0});

  const Answer.unknown({this.helpUsed = 0})
    : type = AnswerType.unknown,
      value = null;

  final AnswerType type;
  final Object? value;

  /// Highest help level used before answering (0 = none).
  final int helpUsed;

  bool get isUnknown => type == AnswerType.unknown;
}
