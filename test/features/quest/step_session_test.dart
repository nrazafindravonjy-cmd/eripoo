import 'dart:convert';

import 'package:eripoo/content/content_pack.dart';
import 'package:eripoo/features/quest/domain/answer.dart';
import 'package:eripoo/features/quest/domain/step_session.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../content/fixture_pack.dart';

final pack = ContentPack.parse(jsonEncode(fixturePack()));

void main() {
  final reflect = pack.step('q01.s02')!;
  QuestionBlock q(String id) => reflect.block(id)! as QuestionBlock;

  test('one block per screen; a required question blocks "next"', () {
    final s = StepSession(step: reflect);
    expect(s.blocks.length, 3);
    expect(s.canGoNext, isFalse);
    s.next();
    expect(s.index, 0);
    s.answer(q('problem'), '  Il manque du pain le soir  ');
    expect(s.answers['problem']!.value, 'Il manque du pain le soir');
    s.next();
    expect(s.current.id, 'who');
    expect(s.canGoNext, isTrue, reason: 'optional question');
    s.next();
    expect(s.isLast, isTrue);
    expect(s.complete, isTrue);
  });

  test('anti-blocking: rephrasing levels, then the example; stuck after 2', () {
    final s = StepSession(step: reflect);
    final first = s.notUnderstood(q('problem'));
    expect(first.rephraseLevel, 1);
    expect(first.showExample, isFalse);
    expect(first.stuck, isFalse);
    final second = s.notUnderstood(q('problem'));
    expect(second.rephraseLevel, 2);
    expect(second.showExample, isTrue);
    expect(second.stuck, isTrue);
    s.nextHint(q('problem'));
    s.nextHint(q('problem'));
    expect(s.help('problem').hintsShown, 1, reason: 'only one hint exists');
    final a = s.answer(q('problem'), 'Le soir');
    expect(a.helpUsed, 4);
  });

  test('"I don\'t know" is a real answer and lets the user go on', () {
    final s = StepSession(step: reflect);
    final a = s.dontKnow(q('problem'));
    expect(a.isUnknown, isTrue);
    expect(s.canGoNext, isTrue);
  });

  test('answers are validated against the question', () {
    final diag = StepSession(step: pack.step('diag.s01')!);
    final stage = pack.step('diag.s01')!.block('stage')! as QuestionBlock;
    expect(() => diag.answer(stage, 'millionaire'), throwsArgumentError);
    expect(diag.answer(stage, 'no_idea').type, AnswerType.choice);
    final s = StepSession(step: reflect);
    expect(() => s.answer(q('problem'), '   '), throwsArgumentError);
    expect(() => s.answer(q('problem'), 'x' * 301), throwsArgumentError);
  });

  test('invalid-answer errors never contain what the user typed', () {
    final s = StepSession(step: reflect);
    try {
      s.answer(q('problem'), 'SECRET ${'x' * 400}');
    } on ArgumentError catch (e) {
      expect(e.toString(), isNot(contains('SECRET')));
    }
  });

  test('fast track keeps only the deliverable', () {
    final s = StepSession(step: reflect, fastTrack: true);
    expect(s.blocks.map((b) => b.id), ['problem']);
  });

  test('resuming starts at the first unanswered question', () {
    final s = StepSession(
      step: reflect,
      answers: {'problem': const Answer(AnswerType.text, 'x')},
    )..resume();
    expect(s.current.id, 'who');
  });
}
