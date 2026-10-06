/// Values that may be attached to a log entry.
///
/// There is deliberately **no** free-text value: user content (answers,
/// names, notes, e-mails, phone numbers, keys, recovery codes) cannot be
/// logged by construction. See docs/SECURITY.md §11.
sealed class LogValue {
  const LogValue();

  /// Rendered form used by sinks.
  String render();
}

final class LogInt extends LogValue {
  const LogInt(this.value);
  final int value;

  @override
  String render() => '$value';
}

final class LogBool extends LogValue {
  const LogBool(this.value);
  final bool value;

  @override
  String render() => '$value';
}

final class LogDuration extends LogValue {
  const LogDuration(this.value);
  final Duration value;

  @override
  String render() => '${value.inMilliseconds}ms';
}

/// An enum value (a code chosen by developers, never user input).
final class LogEnum extends LogValue {
  const LogEnum(this.value);
  final Enum value;

  @override
  String render() => value.name;
}

/// A random technical identifier (UUID). Anything else is redacted.
final class LogId extends LogValue {
  const LogId(this.value);
  final String value;

  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  @override
  String render() => _uuid.hasMatch(value) ? value : '<redacted>';
}

/// An identifier of **public** content (quest, step, mission template...),
/// e.g. `q03.s02`. Anything outside the identifier alphabet is redacted.
final class LogContentId extends LogValue {
  const LogContentId(this.value);
  final String value;

  static final _contentId = RegExp(r'^[a-z][a-z0-9_.-]{0,63}$');

  @override
  String render() => _contentId.hasMatch(value) ? value : '<redacted>';
}
