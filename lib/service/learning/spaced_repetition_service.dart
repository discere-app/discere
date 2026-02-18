import 'dart:math';

import '../../model/learning/flash_card_stat.dart';

class SpacedRepetitionService {
  final double initialEaseFactor = 2.5;
  final int initialInterval = 1; // in Hours
  final int minimumInterval = 1; // in Hours

  /// Methode, um den nächsten Wiederholungstermin zu berechnen
  /// Diese Methode implementiert den SM2-Algorithmus
  FlashCardStat scheduleNextReview(FlashCardStat flashCardStat, int quality) {
    if (quality < 3) {
      flashCardStat.repetition = 0;
      flashCardStat.interval = minimumInterval;
    } else {
      double newEaseFactor = flashCardStat.easeFactor +
          (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02));
      flashCardStat.easeFactor = max(1.3, newEaseFactor);

      if (flashCardStat.repetition == 0) {
        flashCardStat.interval = initialInterval;
      } else if (flashCardStat.repetition == 1) {
        flashCardStat.interval = 6;
      } else {
        flashCardStat.interval =
            (flashCardStat.interval * flashCardStat.easeFactor).round();
      }
      flashCardStat.repetition++;
    }

    flashCardStat.nextReviewDate =
        DateTime.now().add(Duration(hours: flashCardStat.interval));
    return flashCardStat;
  }
}
