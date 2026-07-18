import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/learning/model/deck_stat.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeckConfig daily limits', () {
    test('default newCardsPerDay is 20', () {
      const config = DeckConfig(deckId: 'x');
      expect(config.newCardsPerDay, equals(20));
    });

    test('default maxReviewsPerDay is 200', () {
      const config = DeckConfig(deckId: 'x');
      expect(config.maxReviewsPerDay, equals(200));
    });

    test('copyWith overrides newCardsPerDay only', () {
      const base = DeckConfig(deckId: 'd');
      final updated = base.copyWith(newCardsPerDay: 5);
      expect(updated.newCardsPerDay, equals(5));
      expect(updated.maxReviewsPerDay, equals(200));
      expect(updated.desiredRetention, equals(0.9));
    });

    test('copyWith overrides maxReviewsPerDay only', () {
      const base = DeckConfig(deckId: 'd');
      final updated = base.copyWith(maxReviewsPerDay: 50);
      expect(updated.maxReviewsPerDay, equals(50));
      expect(updated.newCardsPerDay, equals(20));
    });

    test('copyWith can set both limits independently', () {
      const base = DeckConfig(deckId: 'd');
      final updated = base.copyWith(newCardsPerDay: 0, maxReviewsPerDay: 0);
      expect(updated.newCardsPerDay, equals(0));
      expect(updated.maxReviewsPerDay, equals(0));
    });
  });

  group('DeckStat daily counts', () {
    test('defaults to zero today counts', () {
      final stat = DeckStat(10, 5, 3);
      expect(stat.todayNewCount, equals(0));
      expect(stat.todayReviewCount, equals(0));
    });

    test('named parameters set today counts', () {
      final stat = DeckStat(
        10,
        5,
        3,
        todayNewCount: 4,
        todayReviewCount: 12,
      );
      expect(stat.todayNewCount, equals(4));
      expect(stat.todayReviewCount, equals(12));
    });
  });

  group('new-batch budget calculation', () {
    // Mirror the clamping logic from FlashcardService._effectiveNewBatchSize
    int effectiveBatch({
      required int newCardsPerDay,
      required int todayNewCount,
      required int requested,
    }) {
      if (newCardsPerDay <= 0) return requested;
      final budget = newCardsPerDay - todayNewCount;
      return budget.clamp(0, requested);
    }

    test('full budget available → returns requested', () {
      expect(
        effectiveBatch(newCardsPerDay: 20, todayNewCount: 0, requested: 10),
        equals(10),
      );
    });

    test('partial budget → capped to remaining', () {
      expect(
        effectiveBatch(newCardsPerDay: 20, todayNewCount: 15, requested: 10),
        equals(5),
      );
    });

    test('budget exhausted → returns 0', () {
      expect(
        effectiveBatch(newCardsPerDay: 20, todayNewCount: 20, requested: 10),
        equals(0),
      );
    });

    test('budget overflow (count > limit) → returns 0', () {
      expect(
        effectiveBatch(newCardsPerDay: 20, todayNewCount: 25, requested: 10),
        equals(0),
      );
    });

    test('newCardsPerDay = 0 (unlimited) → returns requested', () {
      expect(
        effectiveBatch(newCardsPerDay: 0, todayNewCount: 999, requested: 10),
        equals(10),
      );
    });
  });

  group('review budget calculation', () {
    // Mirror FlashcardService limit logic
    int reviewBudget({
      required int maxReviewsPerDay,
      required int todayReviewCount,
    }) {
      if (maxReviewsPerDay <= 0) return 9999; // unlimited sentinel
      return (maxReviewsPerDay - todayReviewCount).clamp(0, maxReviewsPerDay);
    }

    test('full budget available', () {
      expect(
        reviewBudget(maxReviewsPerDay: 200, todayReviewCount: 0),
        equals(200),
      );
    });

    test('partially used budget', () {
      expect(
        reviewBudget(maxReviewsPerDay: 200, todayReviewCount: 150),
        equals(50),
      );
    });

    test('budget exhausted → 0', () {
      expect(
        reviewBudget(maxReviewsPerDay: 200, todayReviewCount: 200),
        equals(0),
      );
    });

    test('maxReviewsPerDay = 0 → unlimited', () {
      expect(
        reviewBudget(maxReviewsPerDay: 0, todayReviewCount: 999),
        equals(9999),
      );
    });
  });
}
