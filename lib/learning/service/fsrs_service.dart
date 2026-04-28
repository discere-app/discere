import 'dart:math';

import 'package:discere/learning/model/flashcard_stat.dart';

/// The four review grades the user can give a card.
enum ReviewGrade {
  again, // Forgot — show again very soon
  hard, // Remembered with significant difficulty
  good, // Remembered correctly
  easy, // Remembered effortlessly — push far out
}

/// Formats a duration in minutes into a user-friendly short string.
String formatInterval(int totalMinutes) {
  if (totalMinutes < 1) return '<1m';
  if (totalMinutes < 60) return '${totalMinutes}m';
  final hours = totalMinutes ~/ 60;
  if (hours < 24) return '${hours}h';
  final days = hours ~/ 24;
  if (days < 14) return '${days}d';
  if (days < 60) return '${days ~/ 7}w';
  final months = days ~/ 30;
  if (months < 12) return '${months}mo';
  return '${days ~/ 365}y';
}

/// Spaced repetition scheduler based on FSRS 6 with learning/relearning steps.
///
/// FSRS models memory with two variables per card:
///   - Stability (S): how many days until retrievability decays to 90%.
///   - Difficulty (D): intrinsic hardness of the card, in [1, 10].
///
/// Cards progress through a state machine:
///   New → Learning (short-term steps) → Review (FSRS long-term) → Relearning → Review
///
/// During Learning/Relearning, FSRS is not applied — only step timers.
/// Upon graduation from Learning, FSRS initializes stability/difficulty.
/// Upon recovery from Relearning, the card returns to FSRS review.
///
/// Reference: https://github.com/open-spaced-repetition/fsrs-rs
class FsrsService {
  // ─── FSRS 6 default weights ───────────────────────────────────────────────
  static const List<double> _w = [
    0.2120, 1.2931, 2.3065, 8.2956, // w0–w3: initial stability
    6.4133, 0.8334, // w4–w5
    3.0194, 0.0010, // w6–w7
    1.8722, 0.1666, 0.7960, // w8–w10
    1.4835, 0.0614, 0.2629, 1.6483, // w11–w14
    0.6014, 1.8729, // w15–w16
    0.5425, 0.0912, 0.0658, // w17–w19
    0.1542, // w20: power-law decay
  ];

  /// Target retention rate.
  final double requestRetention;

  /// Hard cap on any single interval, in days (~100 years).
  final double maximumIntervalDays;

  /// Short-term steps for new cards before graduating to FSRS.
  final List<Duration> learningSteps;

  /// Short-term steps after a lapse (Again on a review card).
  final List<Duration> relearningSteps;

  /// Power-law decay constant from w[20].
  static final double _decay = _w[20];

  /// Derived factor: 0.9^(−1/decay) − 1.
  static final double _factor = pow(0.9, -1.0 / _decay).toDouble() - 1;

  const FsrsService({
    this.requestRetention = 0.9,
    this.maximumIntervalDays = 36500,
    this.learningSteps = const [
      Duration(minutes: 1),
      Duration(minutes: 10),
    ],
    this.relearningSteps = const [Duration(minutes: 10)],
  });

  // ─── Public API ───────────────────────────────────────────────────────────

  FlashcardStat reviewCard(FlashcardStat stat, ReviewGrade grade) {
    switch (stat.cardState) {
      case CardState.newCard:
        stat = _reviewNewCard(stat, grade);
      case CardState.learning:
        stat = _reviewLearningCard(stat, grade);
      case CardState.review:
        stat = _reviewReviewCard(stat, grade);
      case CardState.relearning:
        stat = _reviewRelearningCard(stat, grade);
    }

    stat.lastReviewDate = DateTime.now();
    return stat;
  }

  Map<ReviewGrade, String> previewIntervals(FlashcardStat stat) {
    return {
      for (final grade in ReviewGrade.values)
        grade: formatInterval(_simulateMinutes(stat, grade)),
    };
  }

  /// Probability of recall right now, given elapsed days and current stability.
  ///
  /// FSRS 6 power-law forgetting curve:
  ///   R(t, S) = (t / S × factor + 1)^(−decay)
  double retrievability(int elapsedDays, double stability) {
    if (stability <= 0) return 1.0;
    return pow(elapsedDays / stability * _factor + 1, -_decay).toDouble();
  }

  // ─── State machine: New card ──────────────────────────────────────────────

  FlashcardStat _reviewNewCard(FlashcardStat stat, ReviewGrade grade) {
    if (learningSteps.isEmpty || grade == ReviewGrade.easy) {
      // No learning steps or Easy → graduate immediately to Review
      final g = _gradeIndex(grade == ReviewGrade.easy ? grade : ReviewGrade.good);
      stat = _initFsrs(stat, g);
      stat.cardState = CardState.review;
      _setFsrsInterval(stat);
    } else {
      // Enter learning steps
      stat.cardState = CardState.learning;
      stat.stepIndex = 0;
      stat = _reviewLearningCard(stat, grade);
    }
    return stat;
  }

  // ─── State machine: Learning card ─────────────────────────────────────────

  FlashcardStat _reviewLearningCard(FlashcardStat stat, ReviewGrade grade) {
    switch (grade) {
      case ReviewGrade.again:
        // Back to first step
        stat.stepIndex = 0;
        _setStepInterval(stat, learningSteps[0]);

      case ReviewGrade.hard:
        // Repeat current step
        _setStepInterval(stat, learningSteps[stat.stepIndex]);

      case ReviewGrade.good:
        if (stat.stepIndex >= learningSteps.length - 1) {
          // Last step completed → graduate to Review
          stat = _graduateFromLearning(stat, grade);
        } else {
          // Advance to next step
          stat.stepIndex++;
          _setStepInterval(stat, learningSteps[stat.stepIndex]);
        }

      case ReviewGrade.easy:
        // Immediate graduation
        stat = _graduateFromLearning(stat, grade);
    }
    return stat;
  }

  FlashcardStat _graduateFromLearning(FlashcardStat stat, ReviewGrade grade) {
    final g = _gradeIndex(grade);
    stat = _initFsrs(stat, g);
    stat.cardState = CardState.review;
    stat.stepIndex = 0;
    _setFsrsInterval(stat);
    return stat;
  }

  // ─── State machine: Review card (FSRS) ────────────────────────────────────

  FlashcardStat _reviewReviewCard(FlashcardStat stat, ReviewGrade grade) {
    final g = _gradeIndex(grade);

    // Normalize: protect against invalid/zero values from DB
    stat.stability = _safeStability(stat.stability);
    stat.difficulty = _safeDifficulty(stat.difficulty);

    if (stat.elapsedDays == 0) {
      // Same-day review
      stat.stability = _shortTermStability(stat.stability, g);
    } else {
      final r = retrievability(stat.elapsedDays, stat.stability);
      if (grade == ReviewGrade.again) {
        stat = _stabilityAfterForgetting(stat, r);
      } else {
        stat = _stabilityAfterRecall(stat, g, r);
      }
    }

    stat = _updateDifficulty(stat, g);

    if (grade == ReviewGrade.again && relearningSteps.isNotEmpty) {
      // Enter relearning steps
      stat.cardState = CardState.relearning;
      stat.stepIndex = 0;
      _setStepInterval(stat, relearningSteps[0]);
    } else {
      _setFsrsInterval(stat);
    }

    return stat;
  }

  // ─── State machine: Relearning card ───────────────────────────────────────

  FlashcardStat _reviewRelearningCard(FlashcardStat stat, ReviewGrade grade) {
    switch (grade) {
      case ReviewGrade.again:
        // Back to first relearning step
        stat.stepIndex = 0;
        _setStepInterval(stat, relearningSteps[0]);

      case ReviewGrade.hard:
        // Repeat current relearning step
        _setStepInterval(stat, relearningSteps[stat.stepIndex]);

      case ReviewGrade.good:
        if (stat.stepIndex >= relearningSteps.length - 1) {
          // Last relearning step → back to Review
          stat = _graduateFromRelearning(stat);
        } else {
          stat.stepIndex++;
          _setStepInterval(stat, relearningSteps[stat.stepIndex]);
        }

      case ReviewGrade.easy:
        // Immediate recovery to Review
        stat = _graduateFromRelearning(stat);
    }
    return stat;
  }

  FlashcardStat _graduateFromRelearning(FlashcardStat stat) {
    stat.cardState = CardState.review;
    stat.stepIndex = 0;
    // Stability was already updated when entering relearning (via Again on review).
    // Set the next interval from current FSRS stability.
    _setFsrsInterval(stat);
    return stat;
  }

  // ─── Interval helpers ─────────────────────────────────────────────────────

  /// Sets nextReviewDate from FSRS stability.
  void _setFsrsInterval(FlashcardStat stat) {
    final intervalDays = _nextInterval(stat.stability);
    stat.nextReviewDate = DateTime.now().add(
      Duration(minutes: (intervalDays * 24 * 60).round()),
    );
  }

  /// Sets nextReviewDate from a learning/relearning step duration.
  void _setStepInterval(FlashcardStat stat, Duration step) {
    stat.nextReviewDate = DateTime.now().add(step);
  }

  // ─── FSRS initialisation ──────────────────────────────────────────────────

  FlashcardStat _initFsrs(FlashcardStat stat, int g) {
    stat.stability = _initialStability(g);
    stat.difficulty = _initialDifficulty(g);
    return stat;
  }

  /// S₀(grade) — starting stability from weights w[0..3].
  double _initialStability(int g) => _w[g - 1];

  /// D₀(grade) = w[4] − e^(w[5] × (grade − 1)) + 1, clamped to [1, 10].
  double _initialDifficulty(int g) {
    final d = _w[4] - exp(_w[5] * (g - 1)) + 1;
    return d.clamp(1.0, 10.0);
  }

  // ─── Stability updates ────────────────────────────────────────────────────

  /// Stability after a successful review (Hard / Good / Easy).
  FlashcardStat _stabilityAfterRecall(FlashcardStat stat, int g, double r) {
    final hardPenalty = g == 2 ? _w[15] : 1.0;
    final easyBonus = g == 4 ? _w[16] : 1.0;
    final s = stat.stability;
    final d = stat.difficulty;

    final newS =
        s *
        (exp(_w[8]) *
                (11 - d) *
                pow(s, -_w[9]) *
                (exp(_w[10] * (1 - r)) - 1) *
                hardPenalty *
                easyBonus +
            1);

    stat.stability = max(s, newS);
    return stat;
  }

  /// Stability after forgetting (Again).
  ///
  /// FSRS 6 adds S_min = S / e^(w[17] × w[18]) as a floor.
  FlashcardStat _stabilityAfterForgetting(FlashcardStat stat, double r) {
    final s = stat.stability;
    final d = stat.difficulty;

    final newS =
        _w[11] *
        pow(d, -_w[12]) *
        (pow(s + 1, _w[13]) - 1) *
        exp((1 - r) * _w[14]);

    final sMin = s / exp(_w[17] * _w[18]);
    stat.stability = max(newS, sMin);

    return stat;
  }

  // ─── Difficulty update ────────────────────────────────────────────────────

  FlashcardStat _updateDifficulty(FlashcardStat stat, int g) {
    final d0Easy = _initialDifficulty(4);
    final deltaD = -_w[6] * (g - 3);
    final nextD = stat.difficulty + deltaD * (10 - stat.difficulty) / 9;

    final revertedD = _w[7] * d0Easy + (1 - _w[7]) * nextD;
    stat.difficulty = revertedD.clamp(1.0, 10.0);
    return stat;
  }

  /// Short-term stability update (w17/w18/w19).
  double _shortTermStability(double s, int g) {
    final sinc = exp(_w[17] * (g - 3 + _w[18])) * pow(s, -_w[19]);
    if (g >= 2) {
      return s * max(sinc, 1.0);
    }
    return s * sinc;
  }

  // ─── Interval calculation ─────────────────────────────────────────────────

  /// Power-law derived interval:
  ///   t = S / factor × (requestRetention^(−1/decay) − 1)
  double _nextInterval(double stability) {
    if (stability <= 0) return 0.0007; // ~1 minute
    final interval =
        stability / _factor * (pow(requestRetention, -1.0 / _decay) - 1);
    return interval.clamp(0.0007, maximumIntervalDays);
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  int _simulateMinutes(FlashcardStat stat, ReviewGrade grade) {
    final sim = FlashcardStat.from(stat);
    final updated = reviewCard(sim, grade);
    final diffMs = updated.nextReviewDate!.difference(DateTime.now()).inMilliseconds;
    return max(0, (diffMs / 60000.0).round());
  }

  int _gradeIndex(ReviewGrade grade) => grade.index + 1;

  double _safeStability(double s) => s.isFinite && s > 0 ? s : _w[0];

  double _safeDifficulty(double d) => d.clamp(1.0, 10.0);
}
