import 'dart:math';

import '../../model/learning/flash_card_stat.dart';

/// Spaced repetition scheduler based on the SM-2 algorithm.
///
/// Note: this implementation uses **hours** as the interval unit,
/// not days as in the original SM-2 spec. This is intentional
/// for short-cycle learning sessions.
class SpacedRepetitionService {
  final double initialEaseFactor = 2.5;
  final int initialInterval = 1; // in Hours
  final int minimumInterval = 1; // in Hours

  /// Methode, um den nächsten Wiederholungstermin zu berechnen
  /// Diese Methode implementiert den SM2-Algorithmus
  FlashCardStat scheduleNextReview(FlashCardStat flashCardStat, int quality) {
    if (quality < 0 || quality > 5) {
      throw ArgumentError('Quality must be between 0 and 5, got $quality');
    }

    double newEaseFactor = flashCardStat.easeFactor +
        (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02));
    newEaseFactor = max(1.3, newEaseFactor);

    int newRepetition;
    int newInterval;

    if (quality < 3) {
      newRepetition = 0;
      newInterval = minimumInterval;
    } else {
      if (flashCardStat.repetition == 0) {
        newInterval = initialInterval;
      } else if (flashCardStat.repetition == 1) {
        newInterval = 6;
      } else {
        newInterval = (flashCardStat.interval * flashCardStat.easeFactor).round();
      }
      newRepetition = flashCardStat.repetition + 1;
    }

    return flashCardStat.copyWith(
      easeFactor: newEaseFactor,
      repetition: newRepetition,
      interval: newInterval,
      nextReviewDate: DateTime.now().add(Duration(hours: newInterval)),
    );
  }
}
