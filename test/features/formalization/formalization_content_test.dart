// Regulatory content (Phase 8, exit criterion "100 % of the information
// sourced"): every fact, document and fee of the real pack points to an
// official source with its place in it; the validator refuses anything
// else; the fee estimate follows the official schedule, at its limits.
import 'package:eripoo/content/content_pack.dart';
import 'package:eripoo/content/content_validator.dart';
import 'package:eripoo/content/formalization.dart';
import 'package:eripoo/content/json_reader.dart';
import 'package:eripoo/features/finance/domain/finance_math.dart';
import 'package:eripoo/features/formalization/domain/creation_fees.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/journey_overrides.dart';

void main() {
  final pack = basePack();
  final content = pack.formalization!;

  group('the real content', () {
    test('every statement cites a declared official source and a place', () {
      expect(validatePack(pack).errors, isEmpty);
      final refs = content.refs.toList();
      expect(refs, isNotEmpty);
      for (final ref in refs) {
        final source = content.source(ref.sourceId);
        expect(source, isNotNull, reason: ref.sourceId);
        expect(source!.url, startsWith('https://www.edbm.mg/'));
        expect(ref.where.trim(), isNotEmpty);
      }
      expect(content.legallyReviewed, isFalse, reason: 'not yet reviewed');
    });

    test('dated: read on 8 October 2026, to check again from January', () {
      for (final s in content.sources) {
        expect(s.consulted, DateTime.utc(2026, 10, 8));
      }
      expect(content.reviewAfter, DateTime.utc(2027, 1, 8));
      final pdf = content.source('edbm_creation_v28')!;
      expect(pdf.version, 'Version 28 : Juillet 2026');
      expect(pdf.sha256, hasLength(64));
    });

    test('the documents of the base procedure are all there', () {
      expect(
        content.checklist.map((c) => c.id),
        containsAll([
          'statutes',
          'identity',
          'lease',
          'location_plan',
          'managers_declaration',
          'original_signatures',
        ]),
      );
      expect(
        content.checklist.firstWhere((c) => c.id == 'proxy').when,
        isNotNull,
        reason: 'only when someone files for you',
      );
    });

    test('no figure the source does not give (no minimum capital)', () {
      final french = [
        for (final t in content.topics) ...[
          for (final f in t.facts) f.text.texts.values.join(' '),
          for (final a in t.advice) a.texts.values.join(' '),
        ],
      ].join(' ').toLowerCase();
      expect(french, isNot(contains('capital minimum')));
      expect(french, isNot(contains('ohada')));
    });
  });

  group('the validator refuses unsourced or incoherent content', () {
    ContentPack withContent(Map<String, Object?> json) => ContentPack(
      packId: pack.packId,
      version: pack.version,
      minAppVersion: pack.minAppVersion,
      blockTypes: pack.blockTypes,
      quests: pack.quests,
      missions: pack.missions,
      sections: pack.sections,
      tools: pack.tools,
      formalization: FormalizationContent.read(JsonReader(json)),
    );
    Map<String, Object?> text(String fr) => {'fr': fr, 'mg': fr, 'en': fr};
    Map<String, Object?> source(String id, {String consulted = '2026-10-08'}) =>
        {
          'id': id,
          'publisher': 'EDBM',
          'title': 'Doc',
          'url': 'https://www.edbm.mg/doc.pdf',
          'consulted': consulted,
          'scope': text('Portée'),
        };

    test('unknown source, uncited source, review date before reading', () {
      final errors = validatePack(
        withContent({
          'review_after': '2026-01-01',
          'legal_review': 'pending',
          'sources': [source('a'), source('unused')],
          'topics': [
            {
              'id': 't',
              'title': text('Sujet'),
              'facts': [
                {'text': text('Fait'), 'source': 'missing', 'where': 'p. 1'},
              ],
            },
          ],
          'checklist': [
            {'id': 'x', 'text': text('Pièce'), 'source': 'a', 'where': 'p. 1'},
          ],
        }),
      ).errors.join('\n');
      expect(errors, contains('unknown source missing'));
      expect(errors, contains('source unused is never cited'));
      expect(errors, contains('review_after must follow'));
    });

    test('a fact without its place, an http address, a bad date', () {
      expect(
        () => FormalizationContent.read(
          JsonReader({
            'review_after': '2027-01-08',
            'legal_review': 'pending',
            'sources': [
              {...source('a'), 'url': 'http://www.edbm.mg/doc.pdf'},
            ],
          }),
        ),
        throwsA(isA<ContentFormatException>()),
      );
      expect(
        () => FormalizationContent.read(
          JsonReader({
            'review_after': '2027-02-30',
            'legal_review': 'pending',
            'sources': [source('a')],
          }),
        ),
        throwsA(isA<ContentFormatException>()),
      );
      expect(
        () =>
            SourcedFact.read(JsonReader({'text': text('Fait'), 'source': 'a'})),
        throwsA(isA<ContentFormatException>()),
        reason: 'the place in the source is required',
      );
      expect(
        () => FormalizationContent.read(
          JsonReader({
            'review_after': '2027-01-08',
            'legal_review': 'maybe',
            'sources': [source('a')],
          }),
        ),
        throwsA(isA<ContentFormatException>()),
      );
    });
  });

  group('creation fees (EDBM schedule, version 28)', () {
    final fees = content.fees!;
    int line(FeeEstimate e, FeeLineKind kind) =>
        e.lines.firstWhere((l) => l.kind == kind).amountMga;

    test('a small SARL, own premises, filed in person', () {
      final e = estimateCreationFees(
        fees,
        const CreationFeeInput(capitalMga: 1000000, taxId: 'trade'),
      );
      expect(line(e, FeeLineKind.statutes), 20000, reason: '0.5 % = 5 000');
      expect(line(e, FeeLineKind.rcs), 16000);
      expect(line(e, FeeLineKind.statistics), 40000);
      expect(line(e, FeeLineKind.syntheticTax), 100000);
      expect(e.lines.map((l) => l.kind), isNot(contains(FeeLineKind.lease)));
      expect(e.lines.map((l) => l.kind), isNot(contains(FeeLineKind.proxy)));
      expect(e.totalMga, 20000 + 16000 + 40000 + 100000);
    });

    test('rented premises and a proxy', () {
      final e = estimateCreationFees(
        fees,
        const CreationFeeInput(
          capitalMga: 10000000,
          taxId: 'artisans',
          monthlyRentMga: 150000,
          leaseMonths: 24,
          represented: true,
        ),
      );
      expect(line(e, FeeLineKind.statutes), 50000, reason: '0.5 % of 10 M');
      expect(line(e, FeeLineKind.lease), 72000, reason: '2 % of 3 600 000');
      expect(line(e, FeeLineKind.proxy), 2000);
      expect(line(e, FeeLineKind.syntheticTax), 50000);
    });

    test('minimums, rounding up, the largest values', () {
      expect(
        line(
          estimateCreationFees(
            fees,
            const CreationFeeInput(capitalMga: 0, taxId: 'primary'),
          ),
          FeeLineKind.statutes,
        ),
        20000,
      );
      expect(
        line(
          estimateCreationFees(
            fees,
            const CreationFeeInput(capitalMga: 4000001, taxId: 'primary'),
          ),
          FeeLineKind.statutes,
        ),
        20001,
        reason: '20 000,005 rounded up',
      );
      final big = estimateCreationFees(
        fees,
        const CreationFeeInput(
          capitalMga: FinanceLimits.maxAmount,
          taxId: 'other',
          monthlyRentMga: FinanceLimits.maxAmount,
          leaseMonths: maxLeaseMonths,
        ),
      );
      expect(line(big, FeeLineKind.statutes), FinanceLimits.maxAmount ~/ 200);
      expect(
        line(big, FeeLineKind.lease),
        FinanceLimits.maxAmount * maxLeaseMonths ~/ 50,
      );
    });

    test('refused inputs', () {
      for (final (input, field) in [
        (
          const CreationFeeInput(capitalMga: -1, taxId: 'other'),
          FeeField.capital,
        ),
        (const CreationFeeInput(capitalMga: 0, taxId: 'unknown'), FeeField.tax),
        (
          const CreationFeeInput(
            capitalMga: 0,
            taxId: 'other',
            monthlyRentMga: 1,
          ),
          FeeField.months,
        ),
        (
          const CreationFeeInput(
            capitalMga: 0,
            taxId: 'other',
            monthlyRentMga: 1,
            leaseMonths: maxLeaseMonths + 1,
          ),
          FeeField.months,
        ),
        (
          const CreationFeeInput(
            capitalMga: 0,
            taxId: 'other',
            monthlyRentMga: 0,
            leaseMonths: 12,
          ),
          FeeField.rent,
        ),
      ]) {
        expect(
          () => estimateCreationFees(fees, input),
          throwsA(
            isA<InvalidFeeInput>().having((e) => e.field, 'field', field),
          ),
        );
      }
    });
  });
}
