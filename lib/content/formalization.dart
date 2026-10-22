import 'json_reader.dart';
import 'localized_text.dart';

/// Regulatory content (CLAUDE.md §18–§19, Phase 8): every statement about
/// rules, documents, fees or offices is tied to an official source with
/// its version and the date it was read. Eripoo's own advice is kept
/// apart and never states a rule. Content only: Eripoo never carries out
/// a procedure.

/// An official document or page that was actually read.
class RegulatorySource {
  const RegulatorySource({
    required this.id,
    required this.publisher,
    required this.title,
    required this.url,
    required this.consulted,
    required this.scope,
    this.version,
    this.sha256,
  });

  final String id;

  /// Who issues it (an official body), as it names itself.
  final String publisher;

  /// Its official title, untranslated.
  final String title;
  final String url;

  /// When Eripoo's authors read it (yyyy-mm-dd).
  final DateTime consulted;

  /// What it covers (e.g. companies, Analamanga).
  final LocalizedText scope;
  final String? version;

  /// Fingerprint of the file read, to check later that it has not changed.
  final String? sha256;

  factory RegulatorySource.read(JsonReader json) {
    json.onlyKeys({
      'id',
      'publisher',
      'title',
      'url',
      'consulted',
      'scope',
      'version',
      'sha256',
    });
    final url = json['url'].string;
    if (!url.startsWith('https://')) json['url'].fail('an https address');
    return RegulatorySource(
      id: json['id'].id,
      publisher: json['publisher'].string,
      title: json['title'].string,
      url: url,
      consulted: readDate(json['consulted']),
      scope: LocalizedText.read(json['scope']),
      version: json['version'].stringOrNull,
      sha256: json['sha256'].stringOrNull,
    );
  }
}

/// A date written yyyy-mm-dd.
DateTime readDate(JsonReader json) {
  final s = json.string;
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
  if (match == null) json.fail('a date yyyy-mm-dd');
  final date = DateTime.utc(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
  if (date.month != int.parse(match.group(2)!)) json.fail('a real date');
  return date;
}

/// Where a statement comes from: a source and the place in it.
class SourceRef {
  const SourceRef(this.sourceId, this.where);

  final String sourceId;

  /// Page, article or section (e.g. "p. 1, Procédure de base").
  final String where;

  static SourceRef read(JsonReader json) =>
      SourceRef(json['source'].id, json['where'].string);
}

/// A rule, a document or a fee, as the source states it.
class SourcedFact {
  const SourcedFact({required this.text, required this.ref});

  final LocalizedText text;
  final SourceRef ref;

  factory SourcedFact.read(JsonReader json) {
    json.onlyKeys({'text', 'source', 'where'});
    return SourcedFact(
      text: LocalizedText.read(json['text']),
      ref: SourceRef.read(json),
    );
  }
}

/// One topic: sourced facts, then Eripoo's advice (never a rule).
class FormalizationTopic {
  const FormalizationTopic({
    required this.id,
    required this.title,
    required this.facts,
    required this.advice,
  });

  final String id;
  final LocalizedText title;
  final List<SourcedFact> facts;
  final List<LocalizedText> advice;

  factory FormalizationTopic.read(JsonReader json) {
    json.onlyKeys({'id', 'title', 'facts', 'advice'});
    return FormalizationTopic(
      id: json['id'].id,
      title: LocalizedText.read(json['title']),
      facts: [for (final f in json['facts'].listOrEmpty) SourcedFact.read(f)],
      advice: [
        for (final a in json['advice'].listOrEmpty) LocalizedText.read(a),
      ],
    );
  }
}

/// A document to prepare, as the source lists it.
class ChecklistItem {
  const ChecklistItem({
    required this.id,
    required this.text,
    required this.ref,
    this.when,
  });

  final String id;
  final LocalizedText text;
  final SourceRef ref;

  /// When it is needed (e.g. "if you rent your premises"); always if null.
  final LocalizedText? when;

  factory ChecklistItem.read(JsonReader json) {
    json.onlyKeys({'id', 'text', 'when', 'source', 'where'});
    return ChecklistItem(
      id: json['id'].id,
      text: LocalizedText.read(json['text']),
      when: json.has('when') ? LocalizedText.read(json['when']) : null,
      ref: SourceRef.read(json),
    );
  }
}

/// The synthetic tax paid at creation, by kind of activity.
class ActivityTax {
  const ActivityTax({
    required this.id,
    required this.label,
    required this.amountMga,
  });

  final String id;
  final LocalizedText label;
  final int amountMga;

  factory ActivityTax.read(JsonReader json) {
    json.onlyKeys({'id', 'label', 'amount_mga'});
    return ActivityTax(
      id: json['id'].id,
      label: LocalizedText.read(json['label']),
      amountMga: json['amount_mga'].integer,
    );
  }
}

/// A fee: a fixed amount, or a rate with a minimum.
class FeeRule {
  const FeeRule({this.amountMga, this.rateBp, this.minimumMga});

  final int? amountMga;

  /// Basis points (0.5 % = 50).
  final int? rateBp;
  final int? minimumMga;

  factory FeeRule.read(JsonReader json) {
    json.onlyKeys({'amount_mga', 'rate_bp', 'minimum_mga'});
    final rule = FeeRule(
      amountMga: json['amount_mga'].intOrNull,
      rateBp: json['rate_bp'].intOrNull,
      minimumMga: json['minimum_mga'].intOrNull,
    );
    final fixed = rule.amountMga != null;
    final rated = rule.rateBp != null && rule.minimumMga != null;
    if (fixed == rated) json.fail('either amount_mga, or rate_bp and minimum');
    return rule;
  }
}

/// The creation fees as the source lists them.
class FeeSchedule {
  const FeeSchedule({
    required this.ref,
    required this.statutes,
    required this.lease,
    required this.proxy,
    required this.rcs,
    required this.statistics,
    required this.syntheticTax,
  });

  final SourceRef ref;

  /// Registration of the articles: a share of the capital.
  final FeeRule statutes;

  /// Registration of a commercial lease: a share of the total rent.
  final FeeRule lease;

  /// Minutes and power of attorney (when someone files for you).
  final FeeRule proxy;
  final FeeRule rcs;
  final FeeRule statistics;
  final List<ActivityTax> syntheticTax;

  factory FeeSchedule.read(JsonReader json) {
    json.onlyKeys({
      'source',
      'where',
      'statutes',
      'lease',
      'proxy',
      'rcs',
      'statistics',
      'synthetic_tax',
    });
    return FeeSchedule(
      ref: SourceRef.read(json),
      statutes: FeeRule.read(json['statutes']),
      lease: FeeRule.read(json['lease']),
      proxy: FeeRule.read(json['proxy']),
      rcs: FeeRule.read(json['rcs']),
      statistics: FeeRule.read(json['statistics']),
      syntheticTax: [
        for (final t in json['synthetic_tax'].list) ActivityTax.read(t),
      ],
    );
  }
}

/// All regulatory content, with when it must be checked again.
class FormalizationContent {
  const FormalizationContent({
    required this.sources,
    required this.reviewAfter,
    required this.legallyReviewed,
    required this.topics,
    required this.checklist,
    required this.fees,
  });

  final List<RegulatorySource> sources;

  /// After this date the app says the information may be out of date.
  final DateTime reviewAfter;

  /// Read and approved by a Malagasy lawyer (not yet).
  final bool legallyReviewed;
  final List<FormalizationTopic> topics;
  final List<ChecklistItem> checklist;
  final FeeSchedule? fees;

  RegulatorySource? source(String id) {
    for (final s in sources) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Every place a statement points to a source.
  Iterable<SourceRef> get refs sync* {
    for (final t in topics) {
      for (final f in t.facts) {
        yield f.ref;
      }
    }
    for (final c in checklist) {
      yield c.ref;
    }
    if (fees != null) yield fees!.ref;
  }

  factory FormalizationContent.read(JsonReader json) {
    json.onlyKeys({
      'sources',
      'review_after',
      'legal_review',
      'topics',
      'checklist',
      'fees',
    });
    final review = json['legal_review'].string;
    if (review != 'pending' && review != 'reviewed') {
      json['legal_review'].fail('pending or reviewed');
    }
    return FormalizationContent(
      sources: [for (final s in json['sources'].list) RegulatorySource.read(s)],
      reviewAfter: readDate(json['review_after']),
      legallyReviewed: review == 'reviewed',
      topics: [
        for (final t in json['topics'].listOrEmpty) FormalizationTopic.read(t),
      ],
      checklist: [
        for (final c in json['checklist'].listOrEmpty) ChecklistItem.read(c),
      ],
      fees: json.has('fees') ? FeeSchedule.read(json['fees']) : null,
    );
  }
}
