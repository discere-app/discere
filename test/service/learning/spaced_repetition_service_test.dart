import 'package:discere/model/learning/flash_card_stat.dart';
import 'package:discere/service/learning/spaced_repetition_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SpacedRepetitionService service;

  setUp(() {
    service = SpacedRepetitionService();
  });

  group('SpacedRepetitionService - SM2 Algorithm', () {
    test('initial review with quality 3 (Pass)', () {
      final stat = FlashCardStat(speciesId: '1', deckId: '1');
      final result = service.scheduleNextReview(stat, 3);

      expect(result.repetition, 1);
      expect(result.interval, 1);
      expect(result.easeFactor, 2.36); // 2.5 + (0.1 - (5-3)*(0.08 + (5-3)*0.02)) = 2.5 + (0.1 - 2*(0.12)) = 2.5 - 0.14 = 2.36
    });

    test('initial review with quality 5 (Perfect)', () {
      final stat = FlashCardStat(speciesId: '1', deckId: '1');
      final result = service.scheduleNextReview(stat, 5);

      expect(result.repetition, 1);
      expect(result.interval, 1);
      expect(result.easeFactor, 2.6); // 2.5 + (0.1 - 0) = 2.6
    });

    test('fail review with quality 2 (Fail)', () {
      final stat = FlashCardStat(speciesId: '1', deckId: '1', repetition: 3, interval: 6);
      final result = service.scheduleNextReview(stat, 2);

      expect(result.repetition, 0);
      expect(result.interval, 1);
      expect(stat.easeFactor, 2.5); // Ease factor doesn't change on failure in this implementation
    });

    test('second review after pass (repetition 1 -> 2)', () {
      final stat = FlashCardStat(speciesId: '1', deckId: '1', repetition: 1, interval: 1, easeFactor: 2.5);
      final result = service.scheduleNextReview(stat, 4);

      expect(result.repetition, 2);
      expect(result.interval, 6);
    });

    test('third review after pass (repetition 2 -> 3)', () {
      final stat = FlashCardStat(speciesId: '1', deckId: '1', repetition: 2, interval: 6, easeFactor: 2.5);
      final result = service.scheduleNextReview(stat, 4);

      expect(result.repetition, 3);
      // newEaseFactor = 2.5 + (0.1 - (5-4)*(0.08 + (5-4)*0.02)) = 2.5 + (0.1 - 1*(0.1)) = 2.5
      expect(result.interval, 15); // 6 * 2.5 = 15
    });

    test('ease factor should not go below 1.3', () {
      final stat = FlashCardStat(speciesId: '1', deckId: '1', easeFactor: 1.3);
      final result = service.scheduleNextReview(stat, 3);

      expect(result.easeFactor, 1.3);
    });
  });
}
