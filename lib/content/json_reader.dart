/// A content pack is malformed. [path] locates the problem (`quests[2].id`)
/// so authors can fix it; the message never contains user data (packs hold
/// only authored content).
class ContentFormatException implements Exception {
  const ContentFormatException(this.path, this.problem);

  final String path;
  final String problem;

  @override
  String toString() => 'ContentFormatException($path: $problem)';
}

/// Strict reader over decoded JSON: unknown keys and wrong types are
/// errors, so a typo in a pack is caught by the validator, not ignored.
class JsonReader {
  JsonReader(this.value, [this.path = r'$']);

  final Object? value;
  final String path;

  Never fail(String problem) => throw ContentFormatException(path, problem);

  Map<String, Object?> get _map {
    final v = value;
    if (v is Map<String, Object?>) return v;
    if (v is Map) return v.cast<String, Object?>();
    fail('expected an object');
  }

  bool get isMap => value is Map;
  bool get isList => value is List;

  /// Fails on any key outside [allowed].
  void onlyKeys(Set<String> allowed) {
    for (final key in _map.keys) {
      if (!allowed.contains(key)) {
        JsonReader(null, '$path.$key').fail('unknown key');
      }
    }
  }

  bool has(String key) => _map.containsKey(key) && _map[key] != null;

  JsonReader operator [](String key) => JsonReader(_map[key], '$path.$key');

  Set<String> get keys => _map.keys.toSet();

  String get string {
    final v = value;
    if (v is String && v.isNotEmpty) return v;
    fail('expected a non-empty string');
  }

  String? get stringOrNull => value == null ? null : string;

  int get integer {
    final v = value;
    if (v is int) return v;
    fail('expected an integer');
  }

  int? get intOrNull => value == null ? null : integer;

  num get number {
    final v = value;
    if (v is num) return v;
    fail('expected a number');
  }

  bool get boolean {
    final v = value;
    if (v is bool) return v;
    fail('expected true or false');
  }

  bool boolOr(bool fallback) => value == null ? fallback : boolean;

  List<JsonReader> get list {
    final v = value;
    if (v is! List) fail('expected a list');
    return [for (var i = 0; i < v.length; i++) JsonReader(v[i], '$path[$i]')];
  }

  List<JsonReader> get listOrEmpty => value == null ? const [] : list;

  /// A stable identifier: lowercase letters, digits, `_` and `.` separators.
  String get id {
    final s = string;
    if (!_idPattern.hasMatch(s)) fail('invalid identifier "$s"');
    return s;
  }

  /// An enum-like token, as stored in facts (`vague_idea`).
  String get token {
    final s = string;
    if (!_tokenPattern.hasMatch(s)) fail('invalid token "$s"');
    return s;
  }

  T oneOf<T extends Enum>(List<T> values) {
    final s = string;
    for (final v in values) {
      if (_snake(v.name) == s) return v;
    }
    fail('expected one of ${values.map((v) => _snake(v.name)).join(', ')}');
  }

  static final _idPattern = RegExp(r'^[a-z][a-z0-9_]*(\.[a-z0-9_]+)*$');
  static final _tokenPattern = RegExp(r'^[a-z0-9_]{1,40}$');
}

/// `fastTracked` → `fast_tracked` (pack JSON uses snake_case).
String _snake(String camel) =>
    camel.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');

String snakeName(Enum value) => _snake(value.name);
