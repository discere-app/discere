import 'dart:math';

import '../../model/learning/flash_card_stat.dart';
import 'spaced_repetition_algorithm.dart';

/// Spaced repetition scheduler based on FSRS-4.5.
///
/// FSRS models memory with two variables per card:
///   - Stability (S): how many days until retrievability decays to 90%.
///   - Difficulty (D): intrinsic hardness of the card, in [1, 10].
///
/// The scheduler targets [requestRetention] (default 90%) and computes the
/// next review date as the day R would drop to that threshold.
///
/// Reference: https://github.com/open-spaced-repetition/fsrs4anki/wiki
class FsrsService implements SpacedRepetitionAlgorithm {
  // ─── FSRS-4.5 default weights ──────────────────────────────────────────────
  //
  // These 19 values were optimised over a large sample of real review data.
  // They can be fine-tuned per user with gradient descent on review history,
  // but the defaults already outperform SM-2 significantly.
  //
  // w[0..3]   — initial stability for grades Again/Hard/Good/Easy (in days)
  // w[4..5]   — initial difficulty curve parameters
  // w[6..7]   — difficulty update: step size and mean-reversion weight
  // w[8..10]  — stability-after-recall multipliers
  // w[11..14] — stability-after-forgetting curve parameters
  // w[15]     — hard penalty (reduces stability gain when grade = Hard)
  // w[16]     — easy bonus  (increases stability gain when grade = Easy)
  // w[17..18] — reserved for future optimisation passes
  static const List<double> _w = [
    0.4072, 1.1829, 3.1262, 15.4722, // w0–w3
    7.2102, 0.5316,                   // w4–w5
    1.0651, 0.0589,                   // w6–w7
    1.5330, 0.1544, 1.0071,           // w8–w10
    1.9395, 0.1100, 0.2900, 2.2700,   // w11–w14
    0.2500, 2.9898,                   // w15–w16
    0.5100, 0.4300,                   // w17–w18
  ];

  /// Target retention rate. The next review is scheduled so that retrievability
  /// equals this value at review time.
  final double requestRetention;

  /// Hard cap on any single interval, in days (~100 years).
  final double maximumIntervalDays;

  const FsrsService({
    this.requestRetention = 0.9,
    this.maximumIntervalDays = 36500,
  });

  // ─── Public API ───────────────────────────────────────────────────────────

  /// Record a review and return the updated [FlashCardStat].
  ///
  /// Call this when the user taps one of the four grade buttons.
  @override
  FlashCardStat reviewCard(FlashCardStat stat, ReviewGrade grade) {
    final g = _gradeIndex(grade);

    if (stat.isNew) {
      stat = _initNewCard(stat, g);
    } else {
      final r = retrievability(stat.elapsedDays, stat.stability);

      if (grade == ReviewGrade.again) {
        stat = _stabilityAfterForgetting(stat, r);
        stat.repetition = 0;
      } else {
        stat = _stabilityAfterRecall(stat, g, r);
        stat.repetition++;
      }

      stat = _updateDifficulty(stat, g);
    }

    final intervalDays = _nextInterval(stat.stability);
    stat.nextReviewDate = DateTime.now()
        .add(Duration(minutes: (intervalDays * 24 * 60).round()));
    stat.lastReviewDate = DateTime.now();
    return stat;
  }

  /// Returns the next interval for each grade as a user-friendly string,
  /// without mutating [stat].
  ///
  /// Use this in the UI to show the consequence of each button before the
  /// user taps, e.g. "Again: 10m  Hard: 1d  Good: 4d  Easy: 12d".
  @override
  Map<ReviewGrade, String> previewIntervals(FlashCardStat stat) {
    return {
      for (final grade in ReviewGrade.values)
        grade: formatInterval(_simulateMinutes(stat, grade)),
    };
  }

  /// Probability of recall right now, given elapsed days and current stability.
  ///
  /// R(t, S) = 0.9^(t / S)
  ///
  /// Returns 1.0 for new cards (no elapsed time).
  double retrievability(int elapsedDays, double stability) {
    if (stability <= 0) return 1.0;
    return pow(0.9, elapsedDays / stability).toDouble();
  }

  // ─── Initialisation ───────────────────────────────────────────────────────

  FlashCardStat _initNewCard(FlashCardStat stat, int g) {
    stat.stability = _initialStability(g);
    stat.difficulty = _initialDifficulty(g);
    stat.repetition = 1;
    return stat;
  }

  /// S₀(grade) — the starting stability comes directly from the first four
  /// weights, one per grade. A first "Easy" review gives ~15 days of stability;
  /// a first "Again" gives ~0.4 days (about 10 hours).
  double _initialStability(int g) => _w[g - 1];

  /// D₀(grade) = w[4] − e^(w[5] × (grade − 1)) + 1, clamped to [1, 10].
  ///
  /// The exponential means an "Again" first answer produces high difficulty,
  /// while "Easy" produces low difficulty.
  double _initialDifficulty(int g) {
    final d = _w[4] - exp(_w[5] * (g - 1)) + 1;
    return d.clamp(1.0, 10.0);
  }

  // ─── Stability updates ────────────────────────────────────────────────────

  /// Stability after a successful review (Hard / Good / Easy).
  ///
  /// S'ᵣ = S × (e^w[8] × (11−D) × S^(−w[9]) × (e^(w[10]×(1−R)) − 1)
  ///            × hardPenalty × easyBonus + 1)
  ///
  /// Key intuitions:
  ///   - (11 − D): easy cards get larger stability gains than hard ones.
  ///   - S^(−w[9]): diminishing returns — the more stable the card already is,
  ///     the smaller the proportional gain.
  ///   - (e^(w[10]×(1−R)) − 1): reviewing late (low R) yields a bigger boost
  ///     than reviewing early. This is what SM-2 gets wrong.
  FlashCardStat _stabilityAfterRecall(
      FlashCardStat stat, int g, double r) {
    final hardPenalty = g == 2 ? _w[15] : 1.0;
    final easyBonus = g == 4 ? _w[16] : 1.0;
    final s = stat.stability;
    final d = stat.difficulty;

    final newS = s *
        (exp(_w[8]) *
                (11 - d) *
                pow(s, -_w[9]) *
                (exp(_w[10] * (1 - r)) - 1) *
                hardPenalty *
                easyBonus +
            1);

    // Stability cannot decrease after a successful recall.
    stat.stability = max(s, newS);
    return stat;
  }

  /// Stability after forgetting (Again).
  ///
  /// S'_f = w[11] × D^(−w[12]) × ((S+1)^w[13] − 1) × e^(w[14]×(1−R))
  ///
  /// Crucially, this is NOT a full reset. A previously stable card recovers
  /// faster than a card that was never learned: (S+1)^w[13] grows with S,
  /// so a card you once knew well bounces back quicker.
  FlashCardStat _stabilityAfterForgetting(FlashCardStat stat, double r) {
    final s = stat.stability;
    final d = stat.difficulty;

    stat.stability = _w[11] *
        pow(d, -_w[12]) *
        (pow(s + 1, _w[13]) - 1) *
        exp((1 - r) * _w[14]);

    return stat;
  }

  // ─── Difficulty update ────────────────────────────────────────────────────

  /// D' = clamp(meanRevert(D − w[6] × (grade − 3)), 1, 10)
  ///
  /// grade = 3 (Good) → no change.
  /// grade < 3        → difficulty increases.
  /// grade > 3        → difficulty decreases.
  ///
  /// The mean-reversion step pulls D gently toward D₀(Easy) each review,
  /// preventing difficulty from drifting to extreme values over time.
  /// This is the fix for SM-2's "ease hell" problem.
  FlashCardStat _updateDifficulty(FlashCardStat stat, int g) {
    final d0Easy = _initialDifficulty(4);
    final rawD = stat.difficulty - _w[6] * (g - 3);
    final revertedD = _w[7] * d0Easy + (1 - _w[7]) * rawD;
    stat.difficulty = revertedD.clamp(1.0, 10.0);
    return stat;
  }

  // ─── Interval calculation ─────────────────────────────────────────────────

  /// t = S × log(requestRetention) / log(0.9), clamped to [1, maximumIntervalDays].
  ///
  /// Derived by solving R(t, S) = requestRetention for t.
  double _nextInterval(double stability) {
    if (stability <= 0) return 0.0007; // ~1 minute
    final interval =
        stability * log(requestRetention) / log(0.9);
    return interval.clamp(0.0007, maximumIntervalDays);
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  /// Simulate a review on a copy of [stat] and return the resulting interval in minutes.
  int _simulateMinutes(FlashCardStat stat, ReviewGrade grade) {
    final sim = FlashCardStat.from(stat);
    final updated = reviewCard(sim, grade);
    return updated.nextReviewDate != null
        ? updated.nextReviewDate!.difference(DateTime.now()).inMinutes.abs()
        : 1;
  }

  /// FSRS grades are 1-indexed (1 = Again … 4 = Easy).
  int _gradeIndex(ReviewGrade grade) => grade.index + 1;
}
