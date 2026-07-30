import 'dart:math';

import 'package:discere/learning/model/flashcard_stat.dart';
import 'package:discere/learning/service/fsrs_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FsrsService sut;

  setUp(() => sut = const FsrsService());

  FlashcardStat newCard() =>
      FlashcardStat(speciesId: 'test-card', deckId: 'test-deck');

  /// Helper: graduate a new card through learning steps to Review state.
  FlashcardStat graduatedCard({ReviewGrade grade = ReviewGrade.good}) {
    var stat = newCard();
    // First review: New → Learning step 0
    stat = sut.reviewCard(stat, ReviewGrade.good);
    expect(stat.cardState, CardState.learning);
    // Advance through steps until graduation
    while (stat.cardState == CardState.learning) {
      stat = sut.reviewCard(stat, grade);
    }
    expect(stat.cardState, CardState.review);
    return stat;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Learning Steps State Machine
  // ═══════════════════════════════════════════════════════════════════════════

  group('new card → learning steps', () {
    test('first review enters learning state', () {
      final stat = sut.reviewCard(newCard(), ReviewGrade.good);

      expect(stat.cardState, CardState.learning);
      expect(stat.stepIndex, 1); // Good advances from step 0 to step 1
      expect(stat.lastReviewDate, isNotNull);
      expect(stat.nextReviewDate, isNotNull);
    });

    test('Again on new card enters learning at step 0', () {
      final stat = sut.reviewCard(newCard(), ReviewGrade.again);

      expect(stat.cardState, CardState.learning);
      expect(stat.stepIndex, 0);
    });

    test('Easy on new card skips learning, graduates immediately', () {
      final stat = sut.reviewCard(newCard(), ReviewGrade.easy);

      expect(stat.cardState, CardState.review);
      // Should have FSRS stability from Easy grade (w3)
      expect(stat.stability, closeTo(8.2956, 0.001));
      expect(stat.difficulty, inInclusiveRange(1.0, 10.0));
    });

    test('Hard on new card stays at learning step 0', () {
      final stat = sut.reviewCard(newCard(), ReviewGrade.hard);

      expect(stat.cardState, CardState.learning);
      expect(stat.stepIndex, 0); // Hard repeats current step
    });
  });

  group('learning step progression', () {
    test('Good advances through steps, then graduates', () {
      var stat = sut.reviewCard(newCard(), ReviewGrade.good);
      expect(stat.cardState, CardState.learning);
      expect(stat.stepIndex, 1); // Advanced from 0 to 1

      // Good on last step (index 1 of [1m, 10m]) → graduate
      stat = sut.reviewCard(stat, ReviewGrade.good);
      expect(stat.cardState, CardState.review);
      expect(stat.stability, greaterThan(0));
    });

    test('Again during learning resets to step 0', () {
      // Get to step 1
      var stat = sut.reviewCard(newCard(), ReviewGrade.good);
      expect(stat.stepIndex, 1);

      // Again → back to step 0
      stat = sut.reviewCard(stat, ReviewGrade.again);
      expect(stat.cardState, CardState.learning);
      expect(stat.stepIndex, 0);
    });

    test('Hard during learning repeats current step', () {
      var stat = sut.reviewCard(newCard(), ReviewGrade.good);
      expect(stat.stepIndex, 1);

      stat = sut.reviewCard(stat, ReviewGrade.hard);
      expect(stat.cardState, CardState.learning);
      expect(stat.stepIndex, 1); // Still on step 1
    });

    test('Easy during learning graduates immediately', () {
      var stat = sut.reviewCard(newCard(), ReviewGrade.again);
      expect(stat.cardState, CardState.learning);
      expect(stat.stepIndex, 0);

      stat = sut.reviewCard(stat, ReviewGrade.easy);
      expect(stat.cardState, CardState.review);
      expect(stat.stability, greaterThan(0));
    });

    test('graduation initializes FSRS stability and difficulty', () {
      var stat = sut.reviewCard(newCard(), ReviewGrade.good);
      stat = sut.reviewCard(stat, ReviewGrade.good); // Graduate

      expect(stat.cardState, CardState.review);
      // Good graduation → w2 stability
      expect(stat.stability, closeTo(2.3065, 0.001));
      expect(stat.difficulty, inInclusiveRange(1.0, 10.0));
    });
  });

  group('learning step intervals', () {
    test('step 0 sets next review ~1 minute from now', () {
      final stat = sut.reviewCard(newCard(), ReviewGrade.again);

      final diff = stat.nextReviewDate!.difference(DateTime.now());
      expect(diff.inSeconds, closeTo(60, 5)); // ~1 minute with tolerance
    });

    test('step 1 sets next review ~10 minutes from now', () {
      var stat = sut.reviewCard(newCard(), ReviewGrade.good);
      // stat is now at step 1 (10m step)

      final diff = stat.nextReviewDate!.difference(DateTime.now());
      expect(diff.inMinutes, closeTo(10, 1));
    });

    test('graduation sets FSRS-based nextReviewDate (days away)', () {
      var stat = sut.reviewCard(newCard(), ReviewGrade.good);
      stat = sut.reviewCard(stat, ReviewGrade.good); // Graduate

      expect(stat.cardState, CardState.review);
      final daysUntilReview = stat.nextReviewDate!
          .difference(DateTime.now())
          .inDays;
      expect(daysUntilReview, greaterThanOrEqualTo(1));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Relearning Steps (Lapse)
  // ═══════════════════════════════════════════════════════════════════════════

  group('lapse → relearning', () {
    test('Again on review card enters relearning', () {
      var stat = graduatedCard();
      stat.lastReviewDate = DateTime.now().subtract(const Duration(days: 3));

      stat = sut.reviewCard(stat, ReviewGrade.again);

      expect(stat.cardState, CardState.relearning);
      expect(stat.stepIndex, 0);
      expect(stat.stability, greaterThan(0)); // Reduced but not zero
    });

    test(
      'Again on review card updates stability before entering relearning',
      () {
        var stat = graduatedCard();
        final stabilityBefore = stat.stability;
        stat.lastReviewDate = DateTime.now().subtract(const Duration(days: 3));

        stat = sut.reviewCard(stat, ReviewGrade.again);

        // Stability should be reduced (forgetting formula applied)
        expect(stat.stability, lessThan(stabilityBefore));
        expect(stat.cardState, CardState.relearning);
      },
    );

    test('Good on last relearning step returns to review', () {
      var stat = graduatedCard();
      stat.lastReviewDate = DateTime.now().subtract(const Duration(days: 3));
      stat = sut.reviewCard(stat, ReviewGrade.again); // Enter relearning
      expect(stat.cardState, CardState.relearning);

      stat = sut.reviewCard(stat, ReviewGrade.good); // Complete relearning
      expect(stat.cardState, CardState.review);
      expect(stat.stepIndex, 0);
      expect(
        stat.nextReviewDate!.difference(DateTime.now()).inDays,
        greaterThanOrEqualTo(1),
      );
    });

    test('Easy on relearning immediately returns to review', () {
      var stat = graduatedCard();
      stat.lastReviewDate = DateTime.now().subtract(const Duration(days: 3));
      stat = sut.reviewCard(stat, ReviewGrade.again);

      stat = sut.reviewCard(stat, ReviewGrade.easy);
      expect(stat.cardState, CardState.review);
    });

    test('Again during relearning resets to step 0', () {
      var stat = graduatedCard();
      stat.lastReviewDate = DateTime.now().subtract(const Duration(days: 3));
      stat = sut.reviewCard(stat, ReviewGrade.again); // Enter relearning

      stat = sut.reviewCard(stat, ReviewGrade.again); // Again in relearning
      expect(stat.cardState, CardState.relearning);
      expect(stat.stepIndex, 0);
    });

    test('Hard during relearning repeats current step', () {
      var stat = graduatedCard();
      stat.lastReviewDate = DateTime.now().subtract(const Duration(days: 3));
      stat = sut.reviewCard(stat, ReviewGrade.again);
      expect(stat.stepIndex, 0);

      stat = sut.reviewCard(stat, ReviewGrade.hard);
      expect(stat.cardState, CardState.relearning);
      expect(stat.stepIndex, 0); // Still on step 0
    });

    test('relearning step sets short interval (~10 minutes)', () {
      var stat = graduatedCard();
      stat.lastReviewDate = DateTime.now().subtract(const Duration(days: 3));
      stat = sut.reviewCard(stat, ReviewGrade.again);

      final diff = stat.nextReviewDate!.difference(DateTime.now());
      expect(diff.inMinutes, closeTo(10, 1)); // Default relearning step: 10m
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Review State (FSRS) — existing behavior preserved
  // ═══════════════════════════════════════════════════════════════════════════

  group('review state (FSRS)', () {
    test('stability increases after successful recall', () {
      var stat = graduatedCard();
      final stabilityBefore = stat.stability;

      stat.lastReviewDate = DateTime.now().subtract(const Duration(days: 3));
      stat = sut.reviewCard(stat, ReviewGrade.good);

      expect(stat.stability, greaterThan(stabilityBefore));
      expect(stat.cardState, CardState.review);
    });

    test('reviewing late gives bigger boost than reviewing early', () {
      var earlyCard = graduatedCard();
      var lateCard = FlashcardStat.from(earlyCard);

      earlyCard.lastReviewDate = DateTime.now().subtract(
        const Duration(days: 1),
      );
      earlyCard = sut.reviewCard(earlyCard, ReviewGrade.good);

      lateCard.lastReviewDate = DateTime.now().subtract(
        const Duration(days: 20),
      );
      lateCard = sut.reviewCard(lateCard, ReviewGrade.good);

      expect(lateCard.stability, greaterThan(earlyCard.stability));
    });

    test('Hard/Good/Easy on review card stay in review state', () {
      for (final grade in [
        ReviewGrade.hard,
        ReviewGrade.good,
        ReviewGrade.easy,
      ]) {
        var stat = graduatedCard();
        stat.lastReviewDate = DateTime.now().subtract(const Duration(days: 3));
        stat = sut.reviewCard(stat, grade);
        expect(stat.cardState, CardState.review);
      }
    });

    test('Again reduces stability (forgetting formula applied)', () {
      var stat = graduatedCard();
      final stabilityBefore = stat.stability;
      stat.lastReviewDate = DateTime.now().subtract(const Duration(days: 3));
      stat = sut.reviewCard(stat, ReviewGrade.again);

      expect(stat.stability, lessThan(stabilityBefore));
    });
  });

  // ─── Difficulty behaviour ──────────────────────────────────────��─────────

  group('difficulty', () {
    test(
      'increases after Hard, unchanged after Good, decreases after Easy',
      () {
        final base = graduatedCard();

        FlashcardStat simulate(ReviewGrade g) {
          var s = FlashcardStat.from(base);
          s.lastReviewDate = DateTime.now().subtract(const Duration(days: 3));
          return sut.reviewCard(s, g);
        }

        final afterHard = simulate(ReviewGrade.hard);
        final afterGood = simulate(ReviewGrade.good);
        final afterEasy = simulate(ReviewGrade.easy);

        expect(afterHard.difficulty, greaterThan(afterGood.difficulty));
        expect(afterEasy.difficulty, lessThan(afterGood.difficulty));
      },
    );

    test('stays within [1, 10] after many Again reviews', () {
      var stat = graduatedCard();
      for (int i = 0; i < 20; i++) {
        stat.lastReviewDate = DateTime.now().subtract(const Duration(days: 1));
        stat = sut.reviewCard(stat, ReviewGrade.again);
        // May enter relearning, recover immediately
        if (stat.cardState == CardState.relearning) {
          stat = sut.reviewCard(stat, ReviewGrade.good);
        }
      }

      expect(stat.difficulty, inInclusiveRange(1.0, 10.0));
    });

    test('stays within [1, 10] after many Easy reviews', () {
      var stat = graduatedCard();
      for (int i = 0; i < 20; i++) {
        stat.lastReviewDate = DateTime.now().subtract(const Duration(days: 5));
        stat = sut.reviewCard(stat, ReviewGrade.easy);
      }

      expect(stat.difficulty, inInclusiveRange(1.0, 10.0));
    });
  });

  // ─── Retrievability (power-law forgetting curve) ─────────────────────────

  group('retrievability', () {
    test('is 1.0 at elapsed = 0', () {
      expect(sut.retrievability(0, 10), equals(1.0));
    });

    test('is 0.9 at elapsed = stability', () {
      expect(sut.retrievability(10, 10), closeTo(0.9, 0.001));
    });

    test('decreases over time', () {
      final r5 = sut.retrievability(5, 10);
      final r10 = sut.retrievability(10, 10);
      final r20 = sut.retrievability(20, 10);

      expect(r5, greaterThan(r10));
      expect(r10, greaterThan(r20));
    });

    test(
      'power-law curve decays slower than exponential at long intervals',
      () {
        final powerLawR = sut.retrievability(50, 10);
        final exponentialR = pow(0.9, 50 / 10).toDouble();

        expect(powerLawR, greaterThan(exponentialR));
      },
    );
  });

  // ─── Preview intervals ───────────────────────────────────────────────────

  group('previewIntervals', () {
    test('returns a value for every grade', () {
      final previews = sut.previewIntervals(newCard());

      expect(previews.keys, containsAll(ReviewGrade.values));
    });

    test('new card previews show learning step intervals', () {
      final previews = sut.previewIntervals(newCard());

      // Again → 1m step
      expect(previews[ReviewGrade.again], equals('1m'));
      // Easy → FSRS graduation interval (days)
      expect(previews[ReviewGrade.easy], isNot(equals('1m')));
    });

    test('review card previews show differentiated FSRS intervals', () {
      var stat = graduatedCard();
      stat.lastReviewDate = DateTime.now().subtract(const Duration(days: 3));
      final previews = sut.previewIntervals(stat);

      for (final grade in ReviewGrade.values) {
        expect(previews[grade], isNotEmpty);
      }
      final uniqueValues = previews.values.toSet();
      expect(uniqueValues.length, greaterThan(1));
    });
  });

  // ─── Short-term stability (same-day reviews on review cards) ─────────────

  group('short-term stability (same-day review)', () {
    test('stability does not decrease after same-day Good', () {
      var stat = graduatedCard();
      final stabilityBefore = stat.stability;

      stat.lastReviewDate = DateTime.now();
      stat = sut.reviewCard(stat, ReviewGrade.good);

      expect(stat.stability, greaterThanOrEqualTo(stabilityBefore));
    });

    test('same-day Again enters relearning', () {
      var stat = graduatedCard();
      stat.lastReviewDate = DateTime.now();

      stat = sut.reviewCard(stat, ReviewGrade.again);
      expect(stat.cardState, CardState.relearning);
    });
  });

  // ─── Stability after failure minimum (S_min) ────────────────────────────

  group('stability after failure minimum (S_min)', () {
    test('S_min prevents stability from dropping too low', () {
      var stat = graduatedCard();
      // Build up high stability
      for (int i = 0; i < 6; i++) {
        stat.lastReviewDate = DateTime.now().subtract(const Duration(days: 10));
        stat = sut.reviewCard(stat, ReviewGrade.good);
      }
      final highStability = stat.stability;

      stat.lastReviewDate = DateTime.now().subtract(const Duration(days: 10));
      stat = sut.reviewCard(stat, ReviewGrade.again);

      final sMin = highStability / exp(0.5425 * 0.0912);
      expect(stat.stability, greaterThanOrEqualTo(sMin - 0.001));
    });
  });

  // ─── No learning steps configuration ─────────────────────────────────────

  group('no learning steps', () {
    test('empty learning steps → new card graduates immediately', () {
      final noStepsSut = const FsrsService(
        learningSteps: [],
        relearningSteps: [],
      );

      final stat = noStepsSut.reviewCard(newCard(), ReviewGrade.good);

      expect(stat.cardState, CardState.review);
      expect(stat.stability, greaterThan(0));
    });

    test('empty relearning steps → Again stays in review', () {
      final noStepsSut = const FsrsService(
        learningSteps: [],
        relearningSteps: [],
      );

      var stat = noStepsSut.reviewCard(newCard(), ReviewGrade.good);
      expect(stat.cardState, CardState.review);

      stat.lastReviewDate = DateTime.now().subtract(const Duration(days: 3));
      stat = noStepsSut.reviewCard(stat, ReviewGrade.again);

      expect(stat.cardState, CardState.review); // No relearning steps
    });
  });

  // ─── Numerical stability guards ─────────────────────────────────────────

  group('numerical stability guards', () {
    test('stability = 0 falls back to minimum stability (w0)', () {
      final stat = FlashcardStat(speciesId: 'sp', deckId: 'dk');
      stat.lastReviewDate = DateTime.now().subtract(const Duration(days: 1));
      stat.cardState = CardState.review;
      stat.stability = 0;
      stat.difficulty = 5;

      final result = sut.reviewCard(stat, ReviewGrade.good);
      expect(result.stability, greaterThan(0));
      expect(result.stability.isFinite, isTrue);
    });

    test('difficulty = 0 clamps to 1.0', () {
      final stat = FlashcardStat(speciesId: 'sp', deckId: 'dk');
      stat.lastReviewDate = DateTime.now().subtract(const Duration(days: 1));
      stat.cardState = CardState.review;
      stat.stability = 5;
      stat.difficulty = 0;

      final result = sut.reviewCard(stat, ReviewGrade.good);
      expect(result.difficulty, greaterThanOrEqualTo(1.0));
    });

    test('infinite stability falls back to w0', () {
      final stat = FlashcardStat(speciesId: 'sp', deckId: 'dk');
      stat.lastReviewDate = DateTime.now().subtract(const Duration(days: 1));
      stat.cardState = CardState.review;
      stat.stability = double.infinity;
      stat.difficulty = 5;

      final result = sut.reviewCard(stat, ReviewGrade.good);
      expect(result.stability.isFinite, isTrue);
    });
  });
}
