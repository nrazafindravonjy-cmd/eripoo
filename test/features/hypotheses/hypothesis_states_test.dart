// Phase 4 exit criterion: the state machines are tested exhaustively.
// Every (from, to) pair is checked against a table written independently
// of the implementation, then every guard on every allowed move.
import 'package:eripoo/features/hypotheses/domain/hypothesis_states.dart';
import 'package:flutter_test/flutter_test.dart';

typedef H = HypothesisStatus;
typedef E = ExperimentStatus;

/// Expected hypothesis moves (docs/PRODUCT_ARCHITECTURE.md §4.1).
const expectedHypothesisMoves = {
  (H.draft, H.toTest),
  (H.draft, H.abandoned),
  (H.toTest, H.testing),
  (H.toTest, H.abandoned),
  (H.testing, H.validated),
  (H.testing, H.invalidated),
  (H.testing, H.inconclusive),
  (H.testing, H.toTest),
  (H.inconclusive, H.testing),
  (H.inconclusive, H.toTest),
  (H.inconclusive, H.abandoned),
};

const expectedExperimentMoves = {
  (E.planned, E.running),
  (E.planned, E.cancelled),
  (E.running, E.done),
  (E.running, E.cancelled),
};

const enough = TestFacts(runningExperiments: 1, results: 1, evidences: 1);

void main() {
  group('hypothesis machine: all ${H.values.length}² pairs', () {
    for (final from in H.values) {
      for (final to in H.values) {
        final allowed = expectedHypothesisMoves.contains((from, to));
        test(
          '${from.name} → ${to.name}: ${allowed ? 'allowed' : 'refused'}',
          () {
            expect(HypothesisMachine.canMove(from, to), allowed);
            if (allowed) {
              HypothesisMachine.check(from, to);
            } else {
              expect(
                () => HypothesisMachine.check(from, to),
                throwsA(
                  isA<InvalidHypothesisTransition>()
                      .having((e) => e.from, 'from', from)
                      .having((e) => e.to, 'to', to),
                ),
              );
            }
          },
        );
      }
    }

    test('no move to the same status, final statuses have no exit', () {
      for (final s in H.values) {
        expect(HypothesisMachine.canMove(s, s), isFalse);
      }
      for (final s in [H.validated, H.invalidated, H.abandoned]) {
        expect(HypothesisMachine.next(s), isEmpty);
      }
    });

    test('every status is reachable from draft', () {
      final seen = {H.draft};
      var frontier = {H.draft};
      while (frontier.isNotEmpty) {
        frontier = {for (final s in frontier) ...HypothesisMachine.next(s)}
            .difference(seen);
        seen.addAll(frontier);
      }
      expect(seen, H.values.toSet());
    });
  });

  group('experiment machine: all ${E.values.length}² pairs', () {
    for (final from in E.values) {
      for (final to in E.values) {
        final allowed = expectedExperimentMoves.contains((from, to));
        test(
          '${from.name} → ${to.name}: ${allowed ? 'allowed' : 'refused'}',
          () {
            expect(ExperimentMachine.canMove(from, to), allowed);
            if (!allowed) {
              expect(
                () => ExperimentMachine.check(from, to),
                throwsA(isA<InvalidExperimentTransition>()),
              );
            }
          },
        );
      }
    }
  });

  group('hypothesis guards on every allowed move', () {
    GuardFailure? failureOf(H from, H to, TestFacts facts) {
      try {
        HypothesisRules.checkMove(from, to, facts);
        return null;
      } on GuardViolation catch (e) {
        return e.failure;
      }
    }

    for (final (from, to) in expectedHypothesisMoves) {
      test('${from.name} → ${to.name} passes with every fact present', () {
        expect(failureOf(from, to, enough), isNull);
      });
    }

    test('testing needs a running experiment (criterion set before)', () {
      for (final from in [H.toTest, H.inconclusive]) {
        expect(
          failureOf(from, H.testing, const TestFacts(results: 3)),
          GuardFailure.noRunningExperiment,
        );
      }
    });

    test('validated / invalidated need a result, then evidence', () {
      for (final to in [H.validated, H.invalidated]) {
        expect(
          failureOf(H.testing, to, const TestFacts(evidences: 2)),
          GuardFailure.noResult,
        );
        expect(
          failureOf(H.testing, to, const TestFacts(results: 2)),
          GuardFailure.noEvidence,
        );
      }
    });

    test('inconclusive needs a result, not evidence', () {
      expect(
        failureOf(H.testing, H.inconclusive, const TestFacts()),
        GuardFailure.noResult,
      );
      expect(
        failureOf(H.testing, H.inconclusive, const TestFacts(results: 1)),
        isNull,
      );
    });

    test('moves without a guard pass with no facts at all', () {
      for (final (from, to) in [
        (H.draft, H.toTest),
        (H.draft, H.abandoned),
        (H.toTest, H.abandoned),
        (H.testing, H.toTest),
        (H.inconclusive, H.toTest),
        (H.inconclusive, H.abandoned),
      ]) {
        expect(failureOf(from, to, const TestFacts()), isNull);
      }
    });

    test('a refused move is refused before any guard', () {
      expect(
        () => HypothesisRules.checkMove(H.validated, H.testing, enough),
        throwsA(isA<InvalidHypothesisTransition>()),
      );
    });
  });

  group('decisions: every (decision, status) pair', () {
    const expected = {
      H.inconclusive: {
        DecisionKind.keepGoing,
        DecisionKind.modify,
        DecisionKind.testMore,
        DecisionKind.abandon,
        DecisionKind.goBack,
      },
      H.validated: {
        DecisionKind.keepGoing,
        DecisionKind.modify,
        DecisionKind.goBack,
      },
      H.invalidated: {
        DecisionKind.keepGoing,
        DecisionKind.modify,
        DecisionKind.goBack,
      },
    };
    for (final status in H.values) {
      for (final decision in DecisionKind.values) {
        final allowed = expected[status]?.contains(decision) ?? false;
        test('${decision.name} on ${status.name}: '
            '${allowed ? 'allowed' : 'refused'}', () {
          expect(
            HypothesisRules.decisionsFor(status).contains(decision),
            allowed,
          );
          if (!allowed) {
            expect(
              () => HypothesisRules.statusAfter(
                decision,
                status,
                const TestFacts(),
              ),
              throwsA(
                isA<GuardViolation>().having(
                  (e) => e.failure,
                  'failure',
                  GuardFailure.decisionNotAllowed,
                ),
              ),
            );
          }
        });
      }
    }

    test('effects: only "test more" and "abandon" change the status', () {
      const none = TestFacts();
      const running = TestFacts(runningExperiments: 1);
      expect(
        HypothesisRules.statusAfter(
          DecisionKind.testMore,
          H.inconclusive,
          none,
        ),
        H.toTest,
      );
      expect(
        HypothesisRules.statusAfter(
          DecisionKind.testMore,
          H.inconclusive,
          running,
        ),
        H.testing,
      );
      expect(
        HypothesisRules.statusAfter(DecisionKind.abandon, H.inconclusive, none),
        H.abandoned,
      );
      for (final status in [H.validated, H.invalidated, H.inconclusive]) {
        for (final d in [
          DecisionKind.keepGoing,
          DecisionKind.modify,
          DecisionKind.goBack,
        ]) {
          expect(HypothesisRules.statusAfter(d, status, none), isNull);
        }
      }
    });

    test('every status a decision leads to is a legal move', () {
      for (final status in H.values) {
        for (final d in HypothesisRules.decisionsFor(status)) {
          for (final facts in [const TestFacts(), enough]) {
            final next = HypothesisRules.statusAfter(d, status, facts);
            if (next != null) {
              expect(HypothesisMachine.canMove(status, next), isTrue);
            }
          }
        }
      }
    });
  });

  group('experiment guards', () {
    test('start needs a criterion; done needs a result', () {
      expect(
        () => ExperimentRules.checkMove(
          E.planned,
          E.running,
          hasCriterion: false,
          results: 0,
        ),
        throwsA(
          isA<GuardViolation>().having(
            (e) => e.failure,
            'failure',
            GuardFailure.noSuccessCriterion,
          ),
        ),
      );
      expect(
        () => ExperimentRules.checkMove(
          E.running,
          E.done,
          hasCriterion: true,
          results: 0,
        ),
        throwsA(
          isA<GuardViolation>().having(
            (e) => e.failure,
            'failure',
            GuardFailure.experimentWithoutResult,
          ),
        ),
      );
      for (final (from, to) in expectedExperimentMoves) {
        ExperimentRules.checkMove(from, to, hasCriterion: true, results: 1);
      }
    });

    test('the criterion is locked from the start of the test', () {
      ExperimentRules.checkCriterionEditable(E.planned);
      for (final s in [E.running, E.done, E.cancelled]) {
        expect(
          () => ExperimentRules.checkCriterionEditable(s),
          throwsA(isA<GuardViolation>()),
        );
      }
    });

    test('metrics: yes out of total', () {
      ExperimentRules.checkMetrics(null, null);
      ExperimentRules.checkMetrics(0, 1);
      ExperimentRules.checkMetrics(7, 10);
      for (final (yes, total) in [
        (1, null),
        (null, 3),
        (4, 3),
        (-1, 3),
        (0, 0),
      ]) {
        expect(
          () => ExperimentRules.checkMetrics(yes, total),
          throwsA(isA<GuardViolation>()),
          reason: '$yes/$total',
        );
      }
    });
  });

  group('texts and confidence', () {
    test('confidence is 1 to 5', () {
      for (var v = 1; v <= 5; v++) {
        HypothesisRules.checkConfidence(v);
      }
      for (final v in [0, 6, -1]) {
        expect(
          () => HypothesisRules.checkConfidence(v),
          throwsA(isA<GuardViolation>()),
        );
      }
    });

    test('statements are trimmed, never empty nor too long', () {
      expect(HypothesisRules.checkText('  Les mères  ', 500), 'Les mères');
      expect(
        () => HypothesisRules.checkText('   ', 500),
        throwsA(isA<GuardViolation>()),
      );
      expect(
        () => HypothesisRules.checkText('x' * 501, 500),
        throwsA(isA<GuardViolation>()),
      );
    });

    test('only draft and to_test statements can be edited in place', () {
      expect(
        {
          for (final s in H.values)
            if (s.isEditable) s,
        },
        {H.draft, H.toTest},
      );
    });
  });

  group('stored tokens', () {
    test('round trip for every value, "continue" for keepGoing', () {
      expect(HypothesisTokens.decision(DecisionKind.keepGoing), 'continue');
      expect(HypothesisTokens.decision(DecisionKind.testMore), 'test_more');
      expect(HypothesisTokens.decision(DecisionKind.goBack), 'go_back');
      for (final d in DecisionKind.values) {
        expect(HypothesisTokens.decisionOf(HypothesisTokens.decision(d)), d);
      }
      for (final values in <List<Enum>>[
        H.values,
        E.values,
        HypothesisCategory.values,
        ExperimentMethod.values,
        EvidenceKind.values,
        EvidenceSubject.values,
      ]) {
        for (final v in values) {
          expect(HypothesisTokens.parse(values, HypothesisTokens.of(v)), v);
        }
      }
      expect(HypothesisTokens.of(H.toTest), 'to_test');
      expect(HypothesisTokens.of(ExperimentMethod.preSale), 'pre_sale');
    });
  });
}
