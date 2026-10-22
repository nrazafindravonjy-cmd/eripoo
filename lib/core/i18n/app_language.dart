/// Languages supported by Eripoo. Malagasy is the product's native language
/// and comes first. Shared by the UI (ARB) and, later, the content system.
enum AppLanguage {
  mg,
  fr,
  en;

  /// Parses a language code (`"mg"`, `"fr-FR"`, ...). Returns null when the
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
