import 'dart:convert';

import 'package:eripoo/content/content_pack.dart';
import 'package:eripoo/content/content_validator.dart';
import 'package:eripoo/content/json_reader.dart';
import 'package:eripoo/content/localized_text.dart';
import 'package:eripoo/core/i18n/app_language.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixture_pack.dart';

ContentPack parse(Map<String, Object?> json) =>
    ContentPack.parse(jsonEncode(json));

/// Deep copy, so each test mutates its own pack.
Map<String, Object?> pack() =>
    jsonDecode(jsonEncode(fixturePack())) as Map<String, Object?>;

List<Object?> questsOf(Map<String, Object?> p) => p['quests']! as List<Object?>;
Map<String, Object?> questAt(Map<String, Object?> p, int i) =>
    questsOf(p)[i]! as Map<String, Object?>;
Map<String, Object?> stepAt(Map<String, Object?> p, int q, int s) =>
    (questAt(p, q)['steps']! as List<Object?>)[s]! as Map<String, Object?>;

void main() {
  group('parsing', () {
    test('the fixture pack parses and validates', () {
      final p = parse(pack());
      expect(p.journey.map((q) => q.id), ['q01', 'q02']);
      expect(p.diagnostic!.id, 'diag');
      expect(p.questOfStep('q01.s02')!.id, 'q01');
      expect(p.step('q01.s02')!.questions.length, 2);
      final report = validatePack(p);
      expect(report.errors, isEmpty);
    });

    test('unknown keys, types and operators are refused with their path', () {
      final p = pack();
      stepAt(p, 1, 0)['colour'] = 'red';
      expect(
        () => parse(p),
        throwsA(
          isA<ContentFormatException>().having(
            (e) => e.path,
            'path',
            r'$.quests[1].steps[0].colour',
          ),
        ),
      );

      final p2 = pack();
      stepAt(p2, 1, 0)['type'] = 'dance';
      expect(() => parse(p2), throwsA(isA<ContentFormatException>()));

      final p3 = pack();
      questAt(p3, 2)['available_when'] = {'eval': 'true'};
      expect(() => parse(p3), throwsA(isA<ContentFormatException>()));
    });

    test('a question without help is refused', () {
      final p = pack();
      final block =
          (stepAt(p, 1, 1)['blocks']! as List<Object?>)[0]!
              as Map<String, Object?>;
      block.remove('help');
      expect(() => parse(p), throwsA(isA<ContentFormatException>()));
    });

    test('a newer pack format is refused', () {
      final p = pack()..['format'] = 2;
      expect(() => parse(p), throwsA(isA<ContentFormatException>()));
    });

    test('not JSON at all', () {
      expect(
        () => ContentPack.parse('{oops'),
        throwsA(isA<ContentFormatException>()),
      );
    });
  });

  group('localizer', () {
    const text = LocalizedText(
      {AppLanguage.fr: 'Bonjour', AppLanguage.en: 'Hello'},
      {AppLanguage.fr: ReviewStatus.needsReview},
    );

    test('falls back along the chain and says which language is shown', () {
      const frOnly = LocalizedText({AppLanguage.fr: 'Bonjour'});
      final fallback = const ContentLocalizer(AppLanguage.en).resolve(frOnly);
      expect(fallback.text, 'Bonjour');
      expect(fallback.language, AppLanguage.fr);
      expect(fallback.status, ReviewStatus.reviewed);

      final en = const ContentLocalizer(AppLanguage.en).resolve(text);
      expect(en.text, 'Hello');
      expect(en.language, AppLanguage.en);
      expect(en.status, ReviewStatus.reviewed);
    });
  });

  group('validator', () {
    List<String> errorsOf(Map<String, Object?> p) =>
        validatePack(parse(p)).errors;

    test('broken references', () {
      final p = pack();
      questAt(p, 2)['available_when'] = {'quest': 'q99', 'is': 'completed'};
      expect(errorsOf(p), contains(contains('unknown quest q99')));
    });

    test('a rule on a fact no step writes, or on an impossible value', () {
      final p = pack();
      questAt(p, 2)['available_when'] = {'fact': 'diag.mood', 'eq': 'happy'};
      expect(errorsOf(p), contains(contains('written by no step')));

      final p2 = pack();
      questAt(p2, 2)['available_when'] = {
        'fact': 'diag.idea_stage',
        'in': ['no_idea', 'rich'],
      };
      expect(errorsOf(p2), contains(contains('never takes the value rich')));
    });

    test('free text never becomes a fact', () {
      final p = pack();
      (stepAt(p, 1, 1)['outputs']! as List<Object?>).add({
        'from': 'problem',
        'fact': 'q01.problem_text',
      });
      expect(errorsOf(p), contains(contains('never free text')));
    });

    test('more than five questions in a row', () {
      final p = pack();
      final blocks = stepAt(p, 1, 1)['blocks']! as List<Object?>;
      blocks.insertAll(0, [for (var i = 0; i < 4; i++) question('extra$i')]);
      expect(errorsOf(p), contains(contains('questions in a row')));
    });

    test('a reflect step must end with a synthesis', () {
      final p = pack();
      (stepAt(p, 1, 1)['blocks']! as List<Object?>).removeLast();
      expect(errorsOf(p), contains(contains('ends with a synthesis')));
    });

    test('fast track may not skip a deliverable', () {
      final p = pack();
      stepAt(p, 1, 1)['fast_track_blocks'] = ['who'];
      expect(errorsOf(p), contains(contains('skip the deliverable problem')));
    });

    test('undeclared block type, unknown mission, duplicate ids', () {
      final p = pack()
        ..['block_types'] = ['text', 'question', 'synthesis', 'mission'];
      expect(errorsOf(p), contains(contains('block type example')));

      final p2 = pack();
      (stepAt(p2, 1, 2)['blocks']! as List<Object?>)[0] = {
        'id': 'go',
        'type': 'mission',
        'mission': 'm.nope',
      };
      expect(errorsOf(p2), contains(contains('unknown mission m.nope')));

      final p3 = pack();
      stepAt(p3, 2, 0)['id'] = 'q01.s01';
      expect(errorsOf(p3), contains(contains('duplicate step id')));
    });

    test('step ids carry their quest id', () {
      final p = pack();
      stepAt(p, 2, 0)['id'] = 'other.s01';
      expect(errorsOf(p), contains(contains('must start with "q02."')));
    });

    test('review status is counted per language', () {
      final report = validatePack(parse(pack()));
      expect(report.reviewCounts[AppLanguage.en]![ReviewStatus.needsReview], 1);
      expect(report.missing[AppLanguage.en], greaterThan(10));
    });
  });
}
