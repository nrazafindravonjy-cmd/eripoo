import '../../../content/content_pack.dart';
import '../../../content/localized_text.dart';
import '../../../core/format/eripoo_formatter.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../finance/application/finance_service.dart';
import '../../finance/presentation/finances_screen.dart';
import '../../formalization/application/preparation_service.dart';
import '../../hypotheses/domain/hypothesis_states.dart';
import '../../tools/presentation/competitors_screen.dart';
import '../application/canvas.dart';
import '../application/project_synthesis.dart';
import 'canvas_screen.dart';

/// One piece of a document: shown on screen and written to the PDF the
/// same way.
sealed class DocItem {
  const DocItem();
}

class DocParagraph extends DocItem {
  const DocParagraph(this.text);
  final String text;
}

class DocLabeled extends DocItem {
  const DocLabeled(this.label, this.text);
  final String label;
  final String text;
}

class DocBullet extends DocItem {
  const DocBullet(this.text);
  final String text;
}

/// A chapter of the file, or a slide of the pitch deck.
class DocPart {
  const DocPart({required this.key, required this.title, required this.items});

  final String key;
  final String title;
  final List<DocItem> items;

  bool get filled => items.isNotEmpty;
}

/// Builds documents from the synthesis. Every sentence is either the
/// user's own text or a computed number in words: nothing is generated to
/// fill a gap (CLAUDE.md §15).
class DocumentBuilder {
  DocumentBuilder({
    required this.synthesis,
    required this.l10n,
    required this.formatter,
    required this.pack,
    required this.text,
  });

  final ProjectSynthesis synthesis;
  final AppLocalizations l10n;
  final EripooFormatter formatter;
  final ContentPack pack;

  /// Content text in the interface language.
  final String Function(LocalizedText) text;

  ProjectSynthesis get _s => synthesis;

  /// The fields of a section, each with its label, empty ones skipped.
  List<DocItem> _section(String key) {
    final schema = pack.section(key);
    if (schema == null) return const [];
    return [
      for (final field in schema.fields)
        if (_s.field(key, field.key) case final value?)
          DocLabeled(text(field.label), value),
    ];
  }

  String _outcome(HypothesisStatus status) => l10n.dossierOutcome(status.name);

  List<DocItem> _concluded(Iterable<ConcludedHypothesis> list) => [
    for (final h in list)
      DocBullet(
        h.conclusion == null
            ? l10n.dossierHypothesis(_outcome(h.outcome), h.statement)
            : l10n.dossierHypothesisWithConclusion(
                _outcome(h.outcome),
                h.statement,
                h.conclusion!,
              ),
      ),
  ];

  List<DocItem> _competitors({int? limit}) => [
    for (final c in _s.competitors.take(limit ?? _s.competitors.length))
      DocBullet(
        c.priceMga == null
            ? l10n.dossierCompetitor(c.name, competitorKindLabel(l10n, c.kind))
            : l10n.dossierCompetitorPrice(
                c.name,
                competitorKindLabel(l10n, c.kind),
                formatter.money(c.priceMga!),
              ),
      ),
  ];

  List<DocItem> _finance() {
    final f = _s.finance;
    final items = <DocItem>[
      if (f.hasUnitCost)
        DocLabeled(
          l10n.financeKindTitle('variableCost'),
          formatter.money(f.unitCost),
        ),
      if (f.ofKind(FinanceKind.fixedCost).isNotEmpty)
        DocLabeled(
          l10n.financeKindTitle('fixedCost'),
          formatter.money(f.fixedMonthly),
        ),
      if (f.ofKind(FinanceKind.investment).isNotEmpty)
        DocLabeled(
          l10n.financeKindTitle('investment'),
          formatter.money(f.investment),
        ),
      if (f.ofKind(FinanceKind.funding).isNotEmpty)
        DocLabeled(
          l10n.financeKindTitle('funding'),
          formatter.money(f.funding),
        ),
      if (f.plan.priceMga != null)
        DocLabeled(l10n.financePlanTitle, formatter.money(f.plan.priceMga!)),
    ];
    final m = f.unitMargin;
    if (m != null) {
      items.add(
        DocParagraph(
          m.isLoss
              ? l10n.financeMarginLoss(formatter.money(-m.unitMargin))
              : l10n.financeMarginResult(
                  formatter.money(m.unitMargin),
                  formatter.percentBp(m.marginBp ?? 0),
                ),
        ),
      );
      items.add(
        DocParagraph(breakEvenSentence(l10n, formatter, f.breakEvenPoint!)),
      );
    }
    final gap = f.gap;
    if (gap != null) {
      items.add(DocParagraph(l10n.financeCashNeed(formatter.money(gap.need))));
      items.add(
        DocParagraph(
          gap.covered
              ? l10n.financeCashCovered
              : l10n.financeCashMissing(formatter.money(gap.missing)),
        ),
      );
    }
    return items;
  }

  List<DocItem> _canvas() => [
    for (final b in canvasOf(_s).where((b) => b.filled))
      DocLabeled(
        l10n.canvasBlock(b.kind.name),
        b.entries.map((e) => canvasEntryText(l10n, formatter, e)).join(' · '),
      ),
  ];

  /// What the work rests on, counted.
  DocItem _groundwork() => DocParagraph(
    l10n.dossierGroundwork(
      _s.observations,
      _s.interviews,
      _s.hypotheses,
      _s.experimentsDone,
    ),
  );

  /// "Ready: 3 / 13", once a document of the checklist is marked ready.
  String? _preparationReady() {
    final items = pack.formalization?.checklist ?? const [];
    final ready = Preparation.fromFields(
      _s.sections[PreparationService.sectionKey] ?? const {},
    ).ready;
    final done = items.where((i) => ready.contains(i.id)).length;
    if (done == 0) return null;
    return l10n.formalizationChecklistProgress(
      formatter.fraction(done, items.length),
    );
  }

  DocPart _part(String key, List<DocItem> items) =>
      DocPart(key: key, title: l10n.dossierChapter(key), items: items);

  /// The entrepreneur's file (CLAUDE.md §15), chapter by chapter.
  List<DocPart> dossier() => [
    _part('summary', _section('vision')),
    _part('problem', [
      ..._section('problem'),
      ..._section('desire'),
      ..._concluded(_s.validated(HypothesisCategory.problem)),
    ]),
    _part('customers', _section('customers')),
    _part('solution', _section('solution')),
    _part('offer', _section('offer')),
    _part('validation', [
      if (_s.concluded.isNotEmpty || _s.observations + _s.interviews > 0)
        _groundwork(),
      ..._concluded(_s.concluded),
    ]),
    _part('market', [..._section('market'), ..._section('swot')]),
    _part('competition', _competitors()),
    _part('businessModel', _canvas()),
    _part('finance', _finance()),
    _part('marketing', _section('marketing')),
    _part('launch', _section('launch')),
    _part('formalization', [
      ..._section('formalization'),
      if (_preparationReady() case final ready?) DocParagraph(ready),
    ]),
    _part('pitch', _section('pitch')),
  ];

  /// The pitch deck: one idea per slide, only slides with something to
  /// show. The cover always exists.
  List<DocPart> pitchDeck() {
    String? first(List<(String, String)> fields) {
      for (final (section, key) in fields) {
        if (_s.field(section, key) case final v?) return v;
      }
      return null;
    }

    DocPart slide(String key, List<DocItem> items) =>
        DocPart(key: key, title: l10n.deckSlide(key), items: items);
    List<DocItem> one(String? value) => [
      if (value != null) DocParagraph(value),
    ];
    final f = _s.finance;
    final slides = [
      DocPart(
        key: 'cover',
        title: _s.project.title,
        items: one(first([('pitch', 'hook'), ('vision', 'summary')])),
      ),
      slide('problem', [
        ...one(first([('pitch', 'problem'), ('problem', 'statement')])),
        if (_s.observations + _s.interviews > 0) _groundwork(),
      ]),
      slide(
        'customers',
        one(
          first([('customers', 'description'), ('customers', 'first_guess')]),
        ),
      ),
      slide('solution', [
        ...one(first([('pitch', 'solution'), ('solution', 'first_idea')])),
        ...one(_s.field('solution', 'advantage')),
      ]),
      slide('proof', [
        ...one(_s.field('pitch', 'proof')),
        ..._concluded(_s.validated().take(3)),
      ]),
      slide('competition', _competitors(limit: 4)),
      slide('model', [
        if (f.plan.priceMga != null)
          DocParagraph(l10n.canvasPrice(formatter.money(f.plan.priceMga!))),
        if (f.hasVolumes)
          DocParagraph(
            l10n.canvasVolume(
              formatter.integer(f.plan.volumeFirst!),
              formatter.integer(f.plan.volumeLast!),
            ),
          ),
        ...one(
          first([('business_model', 'channels'), ('marketing', 'channels')]),
        ),
      ]),
      slide('numbers', [
        for (final item in _finance())
          if (item is DocParagraph) item,
      ]),
      slide('ask', one(_s.field('pitch', 'ask'))),
    ];
    return [slides.first, ...slides.skip(1).where((s) => s.filled)];
  }
}
