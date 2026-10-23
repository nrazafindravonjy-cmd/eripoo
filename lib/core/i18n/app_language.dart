/// Languages supported by Eripoo (Malagasy dropped on 2026-10-23, owner's
/// decision). Shared by the UI (ARB) and the content system.
enum AppLanguage {
  fr,
  en;

  /// Parses a language code (`"fr"`, `"en-US"`, ...). Returns null when the
  /// language is not supported, so callers decide on the fallback.
  static AppLanguage? tryParse(String? code) {
    if (code == null || code.isEmpty) return null;
    final language = code.split(RegExp('[-_]')).first.toLowerCase();
    for (final value in values) {
      if (value.name == language) return value;
    }
    return null;
  }
}
