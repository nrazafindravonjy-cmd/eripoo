import '../core/i18n/app_language.dart';
import 'json_reader.dart';

/// Review state of one language of a text (docs/PRODUCT_ARCHITECTURE.md
/// §6.2). Only [reviewed] text is final; the others are shown but listed
/// by the validator.
enum ReviewStatus {
  /// Written or checked by a native speaker.
  reviewed,

  /// Written by an author, waiting for review.
  needsReview,

  /// Machine draft: never published without human review.
  machineDraft,
}

/// A text of the content in fr / en, each with its review status.
class LocalizedText {
  const LocalizedText(this.texts, [this.status = const {}]);

  final Map<AppLanguage, String> texts;
  final Map<AppLanguage, ReviewStatus> status;

  ReviewStatus statusOf(AppLanguage language) =>
      status[language] ?? ReviewStatus.reviewed;

  /// `{fr: "...", en: "...", status: {en: needs_review}}`.
  factory LocalizedText.read(JsonReader json) {
    json.onlyKeys({'fr', 'en', 'status'});
    final texts = <AppLanguage, String>{
      for (final language in AppLanguage.values)
        if (json.has(language.name)) language: json[language.name].string,
    };
    if (texts.isEmpty) json.fail('no text in any language');
    final status = <AppLanguage, ReviewStatus>{};
    if (json.has('status')) {
      final s = json['status'];
      s.onlyKeys({for (final l in AppLanguage.values) l.name});
      for (final key in s.keys) {
        final language = AppLanguage.tryParse(key)!;
        if (!texts.containsKey(language)) {
          s[key].fail('status for a missing language');
        }
        status[language] = s[key].oneOf(ReviewStatus.values);
      }
    }
    return LocalizedText(texts, status);
  }
}

/// A text resolved for display.
class ResolvedText {
  const ResolvedText(this.text, this.language, this.status);

  final String text;

  /// The language actually shown (may differ from the requested one).
  final AppLanguage language;
  final ReviewStatus status;
}

/// Picks the text to show with a fallback chain per language
/// (docs/ARCHITECTURE.md §5.1). Pure Dart, no Flutter, no `intl`.
class ContentLocalizer {
  const ContentLocalizer(
    this.language, {
    Map<AppLanguage, List<AppLanguage>>? chains,
  }) : _chains = chains ?? defaultChains;

  final AppLanguage language;
  final Map<AppLanguage, List<AppLanguage>> _chains;

  static const defaultChains = {
    AppLanguage.fr: [AppLanguage.fr, AppLanguage.en],
    AppLanguage.en: [AppLanguage.en, AppLanguage.fr],
  };

  ResolvedText resolve(LocalizedText text) {
    for (final candidate in _chains[language]!) {
      final value = text.texts[candidate];
      if (value != null) {
        return ResolvedText(value, candidate, text.statusOf(candidate));
      }
    }
    // A pack always has at least one language (checked when read).
    final entry = text.texts.entries.first;
    return ResolvedText(entry.value, entry.key, text.statusOf(entry.key));
  }

  String call(LocalizedText text) => resolve(text).text;
}
