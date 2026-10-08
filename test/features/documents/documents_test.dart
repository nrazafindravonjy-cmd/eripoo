// The canvas, the file and the pitch deck are built from the work only:
// empty work gives empty blocks and chapters, never made-up text; the PDF
// is produced with the bundled font. Fictitious data only.
import 'dart:io';
import 'dart:typed_data';

import 'package:eripoo/content/localized_text.dart';
import 'package:eripoo/core/format/eripoo_formatter.dart';
import 'package:eripoo/core/i18n/app_language.dart';
import 'package:eripoo/data/local/app_database.dart';
import 'package:eripoo/features/documents/application/canvas.dart';
import 'package:eripoo/features/documents/application/project_synthesis.dart';
import 'package:eripoo/features/documents/presentation/document_model.dart';
import 'package:eripoo/features/documents/presentation/pdf_export.dart';
import 'package:eripoo/features/finance/application/finance_service.dart';
import 'package:eripoo/features/hypotheses/application/research_service.dart';
import 'package:eripoo/features/hypotheses/domain/hypothesis_states.dart';
import 'package:eripoo/features/hypotheses/domain/research.dart';
import 'package:eripoo/features/project/data/project_repository.dart';
import 'package:eripoo/features/tools/application/competitor_service.dart';
import 'package:eripoo/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/journey_overrides.dart';
import '../../helpers/test_database.dart';

void main() {
  final pack = basePack();
  final l10n = lookupAppLocalizations(const Locale('fr'));
  const formatter = EripooFormatter(AppLanguage.fr);
  const localizer = ContentLocalizer(AppLanguage.fr);
  late AppDatabase db;
  late String project;

  setUp(() async {
    db = memoryDatabase();
    project = (await ProjectRepository(db).create('Savon du quartier')).id;
  });
  tearDown(() => db.close());

  Future<ProjectSynthesis> synthesis() async =>
      (await ProjectSynthesisService(db).of(project))!;

  DocumentBuilder builder(ProjectSynthesis s) => DocumentBuilder(
    synthesis: s,
    l10n: l10n,
    formatter: formatter,
    pack: pack,
    text: localizer.call,
  );

  /// A customer hypothesis tested to "validated".
  Future<void> validateCustomerHypothesis() async {
    final research = ResearchService(db);
    final h = await research.createHypothesis(
      projectId: project,
      statement: 'Les vendeuses du marché achètent du savon chaque semaine.',
      category: HypothesisCategory.customer,
      confidenceBefore: 3,
    );
    final e = await research.planExperiment(
      projectId: project,
      method: ExperimentMethod.interview,
      plan: 'Parler à 5 vendeuses.',
      hypothesisIds: [h.id],
      successCriterion: '3 sur 5.',
      sampleTarget: 5,
    );
    await research.startExperiment(e.id);
    final r = await research.recordResult(
      e.id,
      summary: '4 sur 5.',
      yes: 4,
      total: 5,
    );
    await research.addEvidence(
      projectId: project,
      subject: EvidenceSubject.result,
      subjectId: r.id,
      kind: EvidenceKind.note,
      body: 'Notes sans nom.',
    );
    await research.finishExperiment(e.id);
    await research.conclude(
      h.id,
      outcome: HypothesisStatus.validated,
      statement: 'Elles en achètent, surtout le lundi.',
      confidenceAfter: 4,
      experimentId: e.id,
    );
  }

  Future<void> someWork() async {
    final projects = ProjectRepository(db);
    await projects.saveSection(
      projectId: project,
      sectionKey: 'customers',
      fields: {'description': 'Vendeuses du marché'},
    );
    await projects.saveSection(
      projectId: project,
      sectionKey: 'solution',
      fields: {'first_idea': 'Savon livré au marché'},
    );
    await validateCustomerHypothesis();
    final f = FinanceService(db);
    await f.add(
      projectId: project,
      kind: FinanceKind.variableCost,
      label: 'Huile',
      amountMga: 600,
    );
    await f.add(
      projectId: project,
      kind: FinanceKind.fixedCost,
      label: 'Loyer',
      amountMga: 120000,
    );
    await f.savePlan(
      project,
      priceMga: 1000,
      volumeFirst: 100,
      volumeLast: 400,
    );
    await CompetitorService(db).add(
      projectId: project,
      name: 'Épicerie A',
      kind: CompetitorKind.direct,
      priceMga: 900,
    );
  }

  test(
    'nothing done: nine empty blocks, empty chapters, only the cover',
    () async {
      final s = await synthesis();
      final canvas = canvasOf(s);
      expect(canvas.map((b) => b.kind), CanvasBlockKind.values);
      expect(canvas.where((b) => b.filled), isEmpty);
      expect(builder(s).dossier().where((p) => p.filled), isEmpty);
      final deck = builder(s).pitchDeck();
      expect(deck, hasLength(1));
      expect(deck.single.title, 'Savon du quartier');
      expect(deck.single.items, isEmpty, reason: 'no hook written yet');
    },
  );

  test('the canvas shows the user\'s own text, the tested hypotheses and '
      'the numbers, block by block', () async {
    await someWork();
    final s = await synthesis();
    final byKind = {for (final b in canvasOf(s)) b.kind: b};
    final segments = byKind[CanvasBlockKind.segments]!;
    expect(
      segments.entries.whereType<TextEntry>().single.text,
      'Vendeuses du marché',
    );
    expect(segments.tested, isTrue);
    expect(
      byKind[CanvasBlockKind.valueProposition]!.entries.single,
      isA<TextEntry>().having((e) => e.text, 'text', 'Savon livré au marché'),
    );
    final revenue = byKind[CanvasBlockKind.revenue]!.entries;
    expect(revenue.whereType<PriceEntry>().single.priceMga, 1000);
    expect(revenue.whereType<VolumeEntry>().single.last, 400);
    expect(byKind[CanvasBlockKind.costs]!.entries, hasLength(2));
    for (final kind in [
      CanvasBlockKind.channels,
      CanvasBlockKind.relationships,
      CanvasBlockKind.activities,
      CanvasBlockKind.partners,
    ]) {
      expect(byKind[kind]!.filled, isFalse, reason: kind.name);
    }
    expect(sourceOf(CanvasBlockKind.costs), isA<FinanceSource>());
    expect(
      sourceOf(CanvasBlockKind.partners),
      isA<SectionSource>().having(
        (s) => s.section,
        'section',
        'business_model',
      ),
    );
  });

  test('the file: chapters written by the work, the rest left to do', () async {
    await someWork();
    final parts = builder(await synthesis()).dossier();
    final ready = {
      for (final p in parts)
        if (p.filled) p.key,
    };
    expect(ready, {
      'customers',
      'solution',
      'validation',
      'competition',
      'businessModel',
      'finance',
    });
    final validation = parts.firstWhere((p) => p.key == 'validation');
    final texts = [
      for (final i in validation.items)
        switch (i) {
          DocParagraph(:final text) => text,
          DocBullet(:final text) => text,
          DocLabeled(:final text) => text,
        },
    ];
    expect(
      texts,
      contains(
        'Confirmée : Les vendeuses du marché achètent du savon chaque '
        'semaine. — Elles en achètent, surtout le lundi.',
      ),
    );
    expect(
      texts.first,
      'Fondé sur aucune observation, aucune rencontre, 1 hypothèse et 1 test '
      'terminé.',
    );
    final finance = parts.firstWhere((p) => p.key == 'finance');
    expect(
      finance.items.whereType<DocParagraph>().map((p) => p.text),
      contains(
        'Pour payer tes frais du mois, vends au moins 300 unités par mois '
        '(300 000 Ar de ventes).',
      ),
    );
  });

  test('the pitch deck keeps only slides with something to show', () async {
    await someWork();
    final deck = builder(await synthesis()).pitchDeck();
    expect(deck.map((s) => s.key), [
      'cover',
      'customers',
      'solution',
      'proof',
      'competition',
      'model',
      'numbers',
    ]);
  });

  group('PDF', () {
    Future<List<int>> build(PdfKind kind, List<DocPart> parts) async {
      Future<ByteData> font(String name) async =>
          ByteData.sublistView(await File('assets/fonts/$name').readAsBytes());
      return buildPdf(
        kind: kind,
        title: 'Savon du quartier',
        parts: parts,
        missing: const [],
        labels: PdfLabels(
          missingTitle: 'À faire',
          footer: (page, pages) => 'Eripoo $page/$pages',
        ),
        regular: await font('Roboto-Regular.ttf'),
        bold: await font('Roboto-Bold.ttf'),
      );
    }

    test(
      'the file and the slides are valid PDFs, one page per slide',
      () async {
        await someWork();
        final b = builder(await synthesis());
        final dossier = await build(PdfKind.dossier, b.dossier());
        expect(String.fromCharCodes(dossier.take(5)), '%PDF-');
        final deck = b.pitchDeck();
        final slides = await build(PdfKind.pitchDeck, deck);
        final pages = RegExp(r'/Type\s*/Page\b')
            .allMatches(String.fromCharCodes(slides))
            .length;
        expect(pages, deck.length);
      },
    );

    test(
      'Malagasy, French and typographic characters do not break it',
      () async {
        final bytes = await build(PdfKind.dossier, const [
          DocPart(
            key: 'summary',
            title: 'Famintinana',
            items: [
              DocParagraph('Mpivarotra eny an-tsena — « savony » ô à é ñ'),
              DocLabeled('Prix', '1 000 Ar'),
            ],
          ),
        ]);
        expect(bytes, isNotEmpty);
      },
    );

    test('file names: no path, no strange character', () {
      expect(
        exportFileName('Savon / du quartier !', PdfKind.dossier),
        'Savon_du_quartier_dossier.pdf',
      );
      expect(exportFileName('../..', PdfKind.pitchDeck), 'eripoo_pitch.pdf');
      expect(exportFileName('é' * 60, PdfKind.dossier).length, 40 + 12);
    });
  });
}
