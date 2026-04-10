import 'dart:math';

import 'package:discere/learning/model/flash_card_stat.dart';
import 'spaced_repetition_algorithm.dart';

/// Spaced repetition scheduler based on the SM-2 algorithm.
///
/// Note: this implementation uses **hours** as the interval unit,
/// not days as in the original SM-2 spec. This is intentional
/// for short-cycle learning sessions.
class SpacedRepetitionService implements SpacedRepetitionAlgorithm {
  final double initialEaseFactor = 2.5;
  final int initialInterval = 1; // in Hours
  final int minimumInterval = 1; // in Hours

  @override
  FlashCardStat reviewCard(FlashCardStat stat, ReviewGrade grade) {
    int quality;
    switch (grade) {
      case ReviewGrade.again:
        quality = 0;
        break;
      case ReviewGrade.hard:
        quality = 3;
        break;
      case ReviewGrade.good:
        quality = 4;
        break;
      case ReviewGrade.easy:
        quality = 5;
        break;
    }
    return scheduleNextReview(stat, quality);
  }

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
      lastReviewDate: DateTime.now(),
    );
  }

  @override
  Map<ReviewGrade, String> previewIntervals(FlashCardStat stat) {
    return {
      for (final grade in ReviewGrade.values)
        grade: _simulatePreview(stat, grade),
    };
  }

  String _simulatePreview(FlashCardStat stat, ReviewGrade grade) {
    final sim = FlashCardStat.from(stat);
    final result = reviewCard(sim, grade);
    // SM-2 interval is in hours → convert to minutes for formatInterval
    return formatInterval(result.interval * 60);
  }
}
