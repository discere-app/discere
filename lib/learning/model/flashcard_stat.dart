import 'package:discere/learning/model/deck_config.dart';

/// The lifecycle state of a flashcard in the learning system.
///
/// ```
/// New → Learning → Review → Relearning → Review
///          ↑_Again___|          ↑__Again__|
/// ```
enum CardState {
  /// Never seen by the user. Waiting to be activated.
  newCard,

  /// In short-term learning steps (e.g. 1m, 10m) before graduating to FSRS.
  learning,

  /// In the FSRS long-term schedule. Normal spaced repetition.
  review,

  /// Re-learning after a lapse (Again on a review card). Short-term steps
  /// before returning to FSRS.
  relearning,
}

class FlashcardStat {
  final String speciesId;
  final String deckId;
  final LearningMode learningMode;

  // FSRS fields
  double stability;
  double difficulty;
  DateTime? lastReviewDate;

  // Common field
  DateTime? nextReviewDate;

  // Learning steps state
  CardState cardState;
  int stepIndex;

  FlashcardStat({
    required this.speciesId,
    required this.deckId,
    this.learningMode = LearningMode.species,
    this.stability = 0.0,
    this.difficulty = 0.0,
    this.lastReviewDate,
    this.nextReviewDate,
    this.cardState = CardState.newCard,
    this.stepIndex = 0,
  });

  /// True only if this card has never been reviewed.
  bool get isNew => lastReviewDate == null;

  int get elapsedDays => lastReviewDate == null
      ? 0
      : DateTime.now().difference(lastReviewDate!).inDays;

  FlashcardStat copyWith({
    String? speciesId,
    String? deckId,
    LearningMode? learningMode,
    double? stability,
    double? difficulty,
    DateTime? lastReviewDate,
    DateTime? nextReviewDate,
    CardState? cardState,
    int? stepIndex,
  }) {
    return FlashcardStat(
      speciesId: speciesId ?? this.speciesId,
      deckId: deckId ?? this.deckId,
      learningMode: learningMode ?? this.learningMode,
      stability: stability ?? this.stability,
      difficulty: difficulty ?? this.difficulty,
      lastReviewDate: lastReviewDate ?? this.lastReviewDate,
      nextReviewDate: nextReviewDate ?? this.nextReviewDate,
      cardState: cardState ?? this.cardState,
      stepIndex: stepIndex ?? this.stepIndex,
    );
  }

  /// Create a clone from an existing instance
  factory FlashcardStat.from(FlashcardStat stat) {
    return stat.copyWith();
  }
}
