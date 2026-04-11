import 'dart:math';

import 'package:discere/learning/model/flashcard_stat.dart';
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
  FlashcardStat reviewCard(FlashcardStat stat, ReviewGrade grade) {
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
  FlashcardStat scheduleNextReview(FlashcardStat flashcardStat, int quality) {
    if (quality < 0 || quality > 5) {
      throw ArgumentError('Quality must be between 0 and 5, got $quality');
    }

    double newEaseFactor =
        flashcardStat.easeFactor +
        (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02));
    newEaseFactor = max(1.3, newEaseFactor);

    int newRepetition;
    int newInterval;

    if (quality < 3) {
      newRepetition = 0;
      newInterval = minimumInterval;
    } else {
      if (flashcardStat.repetition == 0) {
        newInterval = initialInterval;
      } else if (flashcardStat.repetition == 1) {
        newInterval = 6;
      } else {
        newInterval = (flashcardStat.interval * flashcardStat.easeFactor)
            .round();
      }
      newRepetition = flashcardStat.repetition + 1;
    }

    return flashcardStat.copyWith(
      easeFactor: newEaseFactor,
      repetition: newRepetition,
      interval: newInterval,
      nextReviewDate: DateTime.now().add(Duration(hours: newInterval)),
      lastReviewDate: DateTime.now(),
    );
  }

  @override
  Map<ReviewGrade, String> previewIntervals(FlashcardStat stat) {
    return {
      for (final grade in ReviewGrade.values)
        grade: _simulatePreview(stat, grade),
    };
  }

  String _simulatePreview(FlashcardStat stat, ReviewGrade grade) {
    final sim = FlashcardStat.from(stat);
    final result = reviewCard(sim, grade);
    // SM-2 interval is in hours → convert to minutes for formatInterval
    return formatInterval(result.interval * 60);
  }
}
