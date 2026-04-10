import 'package:flutter_test/flutter_test.dart';

import 'package:discere/learning/model/flash_card_stat.dart';
import 'package:discere/learning/service/fsrs_service.dart';
import 'package:discere/learning/service/spaced_repetition_algorithm.dart';

void main() {
  late FsrsService sut;

  setUp(() => sut = const FsrsService());

  FlashCardStat newCard() => FlashCardStat(speciesId: 'test-card', deckId: 'test-deck');

  // ─── New card initialisation ─────────────────────────────────────────────

  group('new card', () {
    test('Good on first review sets stability > 0 and difficulty in range', () {
      final stat = sut.reviewCard(newCard(), ReviewGrade.good);

      expect(stat.stability, greaterThan(0));
      expect(stat.difficulty, inInclusiveRange(1.0, 10.0));
      expect(stat.repetition, 1);
    });

    test('Easy gives higher initial stability than Again', () {
      final easy = sut.reviewCard(newCard(), ReviewGrade.easy);
      final again = sut.reviewCard(newCard(), ReviewGrade.again);

      expect(easy.stability, greaterThan(again.stability));
    });

    test('Easy gives lower initial difficulty than Again', () {
      final easy = sut.reviewCard(newCard(), ReviewGrade.easy);
      final again = sut.reviewCard(newCard(), ReviewGrade.again);

      expect(easy.difficulty, lessThan(again.difficulty));
    });

    test('nextReviewDate is set and in the future', () {
      final stat = sut.reviewCard(newCard(), ReviewGrade.good);

      expect(stat.nextReviewDate, isNotNull);
      expect(stat.nextReviewDate!.isAfter(DateTime.now()), isTrue);
    });
  });

  // ─── Stability behaviour ─────────────────────────────────────────────────

  group('stability', () {
    test('increases after successful recall', () {
      var stat = sut.reviewCard(newCard(), ReviewGrade.good);
      final stabilityBefore = stat.stability;

      stat.lastReviewDate = DateTime.now().subtract(const Duration(days: 3));
      stat = sut.reviewCard(stat, ReviewGrade.good);

      expect(stat.stability, greaterThan(stabilityBefore));
    });

    test('reviewing early (high R) gives smaller boost than reviewing late (low R)', () {
      var earlyCard = sut.reviewCard(newCard(), ReviewGrade.good);
      var lateCard = FlashCardStat.from(earlyCard);

      // Early review: only 1 day elapsed
      earlyCard.lastReviewDate = DateTime.now().subtract(const Duration(days: 1));
      earlyCard = sut.reviewCard(earlyCard, ReviewGrade.good);

      // Late review: 20 days elapsed — lower R
      lateCard.lastReviewDate = DateTime.now().subtract(const Duration(days: 20));
      lateCard = sut.reviewCard(lateCard, ReviewGrade.good);

      expect(lateCard.stability, greaterThan(earlyCard.stability));
    });

    test('Again reduces stability but does not zero it on an established card', () {
      var stat = sut.reviewCard(newCard(), ReviewGrade.good);
      // Simulate several successful reviews to build up stability
      for (int i = 0; i < 4; i++) {
        stat.lastReviewDate = DateTime.now().subtract(const Duration(days: 5));
        stat = sut.reviewCard(stat, ReviewGrade.good);
      }
      final highStability = stat.stability;

      stat.lastReviewDate = DateTime.now().subtract(const Duration(days: 5));
      stat = sut.reviewCard(stat, ReviewGrade.again);

      expect(stat.stability, greaterThan(0));
      expect(stat.stability, lessThan(highStability));
    });

    test('Again resets repetition counter', () {
      var stat = sut.reviewCard(newCard(), ReviewGrade.good);
      stat.lastReviewDate = DateTime.now().subtract(const Duration(days: 3));
      stat = sut.reviewCard(stat, ReviewGrade.again);

      expect(stat.repetition, 0);
    });
  });

  // ─── Difficulty behaviour ────────────────────────────────────────────────

  group('difficulty', () {
    test('increases after Hard, unchanged after Good, decreases after Easy', () {
      final base = sut.reviewCard(newCard(), ReviewGrade.good);

      FlashCardStat simulate(ReviewGrade g) {
        var s = FlashCardStat.from(base);
        s.lastReviewDate = DateTime.now().subtract(const Duration(days: 3));
        return sut.reviewCard(s, g);
      }

      final afterHard = simulate(ReviewGrade.hard);
      final afterGood = simulate(ReviewGrade.good);
      final afterEasy = simulate(ReviewGrade.easy);

      expect(afterHard.difficulty, greaterThan(afterGood.difficulty));
      expect(afterEasy.difficulty, lessThan(afterGood.difficulty));
    });

    test('stays within [1, 10] after many Again reviews', () {
      var stat = sut.reviewCard(newCard(), ReviewGrade.again);
      for (int i = 0; i < 20; i++) {
        stat.lastReviewDate = DateTime.now().subtract(const Duration(days: 1));
        stat = sut.reviewCard(stat, ReviewGrade.again);
      }

      expect(stat.difficulty, inInclusiveRange(1.0, 10.0));
    });

    test('stays within [1, 10] after many Easy reviews', () {
      var stat = sut.reviewCard(newCard(), ReviewGrade.easy);
      for (int i = 0; i < 20; i++) {
        stat.lastReviewDate = DateTime.now().subtract(const Duration(days: 5));
        stat = sut.reviewCard(stat, ReviewGrade.easy);
      }

      expect(stat.difficulty, inInclusiveRange(1.0, 10.0));
    });
  });

  // ─── Retrievability ──────────────────────────────────────────────────────

  group('retrievability', () {
    test('is 1.0 at elapsed = 0', () {
      expect(sut.retrievability(0, 10), equals(1.0));
    });

    test('is 0.9 at elapsed = stability', () {
      expect(sut.retrievability(10, 10), closeTo(0.9, 0.001));
    });

    test('decreases over time', () {
      final r5  = sut.retrievability(5, 10);
      final r10 = sut.retrievability(10, 10);
      final r20 = sut.retrievability(20, 10);

      expect(r5, greaterThan(r10));
      expect(r10, greaterThan(r20));
    });
  });

  // ─── Preview intervals ───────────────────────────────────────────────────

  group('previewIntervals', () {
    test('returns a value for every grade', () {
      final previews = sut.previewIntervals(newCard());

      expect(previews.keys, containsAll(ReviewGrade.values));
    });

    test('all grades produce non-empty, differentiated interval strings', () {
      var stat = sut.reviewCard(newCard(), ReviewGrade.good);
      stat.lastReviewDate = DateTime.now().subtract(const Duration(days: 3));
      final previews = sut.previewIntervals(stat);

      // All grades should produce a non-empty string
      for (final grade in ReviewGrade.values) {
        expect(previews[grade], isNotEmpty);
      }

      // The algorithm should differentiate — not all previews should be equal
      final uniqueValues = previews.values.toSet();
      expect(uniqueValues.length, greaterThan(1));
    });

    test('preview for 3.0 day stability shows exactly 3d', () {
      final newPreviews = sut.previewIntervals(newCard());
      // Good (w2) is 3.0 days -> "3d"
      expect(newPreviews[ReviewGrade.good], equals('3d'));
    });
  });

  group('same-day reviews (FSRS-5)', () {
    test('stability increases slightly after same-day Good review', () {
      final base = sut.reviewCard(newCard(), ReviewGrade.good);
      final stabilityBefore = base.stability;

      // Same day review: elapsedDays = 0
      base.lastReviewDate = DateTime.now();
      final after = sut.reviewCard(base, ReviewGrade.good);

      expect(after.stability, greaterThan(stabilityBefore));
      // Formula: S' = S * e^(w17 * (G - 3 + w18))
      // For G=3: S' = S * e^(0.51 * 0.43) ≈ S * 1.245
      expect(after.stability, closeTo(stabilityBefore * 1.245, 0.001));
    });

    test('stability decreases after same-day Again review', () {
      final base = sut.reviewCard(newCard(), ReviewGrade.good);
      final stabilityBefore = base.stability;

      base.lastReviewDate = DateTime.now();
      final after = sut.reviewCard(base, ReviewGrade.again);

      expect(after.stability, lessThan(stabilityBefore));
      // For G=1: S' = S * e^(0.51 * (1 - 3 + 0.43)) ≈ S * 0.449
      expect(after.stability, closeTo(stabilityBefore * 0.449, 0.001));
    });

    test('repetition increments after same-day Good review', () {
      final base = sut.reviewCard(newCard(), ReviewGrade.good);
      expect(base.repetition, 1);

      base.lastReviewDate = DateTime.now();
      final after = sut.reviewCard(base, ReviewGrade.good);

      expect(after.repetition, 2);
    });

    test('repetition resets after same-day Again review', () {
      final base = sut.reviewCard(newCard(), ReviewGrade.good);
      expect(base.repetition, 1);

      base.lastReviewDate = DateTime.now();
      final after = sut.reviewCard(base, ReviewGrade.again);

      expect(after.repetition, 0);
    });

    test('interval (integer) field is synchronized with stability', () {
      final stat = sut.reviewCard(newCard(), ReviewGrade.easy);
      
      // Stability for first Easy is 5.0
      expect(stat.stability, equals(5.0));
      expect(stat.interval, equals(5));
    });

    test('initialized card (nextReviewDate set) but no lastReviewDate should be isNew', () {
      final stat = FlashCardStat(speciesId: 'sp1', deckId: 'deck1');
      stat.nextReviewDate = DateTime.now();
      expect(stat.isNew, isTrue);
    });

    test('reviewing an initialized card for the first time triggers _initNewCard', () {
      final stat = FlashCardStat(speciesId: 'sp1', deckId: 'deck1');
      stat.nextReviewDate = DateTime.now();
      
      final result = sut.reviewCard(stat, ReviewGrade.good);
      
      // Should have w2 stability (3.0) and repetition 1
      expect(result.stability, equals(3.0)); 
      expect(result.repetition, equals(1));
      expect(result.lastReviewDate, isNotNull);
    });
  });

  group('numerical stability guards', () {
    test('stability = 0 falls back to minimum stability (w0)', () {
      final stat = FlashCardStat(speciesId: 'sp', deckId: 'dk');
      stat.lastReviewDate = DateTime.now().subtract(const Duration(days: 1));
      stat.stability = 0;
      stat.difficulty = 5;

      final result = sut.reviewCard(stat, ReviewGrade.good);
      // It should have used w0 (0.375) as base instead of 0
      expect(result.stability, greaterThan(0));
      expect(result.stability.isFinite, isTrue);
    });

    test('difficulty = 0 clamps to 1.0', () {
      final stat = FlashCardStat(speciesId: 'sp', deckId: 'dk');
      stat.lastReviewDate = DateTime.now().subtract(const Duration(days: 1));
      stat.stability = 5;
      stat.difficulty = 0; // Invalid

      final result = sut.reviewCard(stat, ReviewGrade.good);
      expect(result.difficulty, greaterThanOrEqualTo(1.0));
    });

    test('infinite stability falls back to w0', () {
      final stat = FlashCardStat(speciesId: 'sp', deckId: 'dk');
      stat.lastReviewDate = DateTime.now().subtract(const Duration(days: 1));
      stat.stability = double.infinity;
      stat.difficulty = 5;

      final result = sut.reviewCard(stat, ReviewGrade.good);
      expect(result.stability.isFinite, isTrue);
    });
  });
}
