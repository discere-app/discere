import 'package:flutter_test/flutter_test.dart';

import 'package:discere/model/learning/flash_card_stat.dart';
import 'package:discere/service/learning/fsrs_service.dart';
import 'package:discere/service/learning/spaced_repetition_algorithm.dart';

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
  });
}
