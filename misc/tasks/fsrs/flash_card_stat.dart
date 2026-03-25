/// Represents the scheduling state of a single flashcard.
///
/// This model supports the FSRS algorithm. The old SM-2 fields
/// [easeFactor] and [interval] are no longer used and can be removed
/// once the migration is complete.
class FlashCardStat {
  /// Unique identifier of the flashcard this stat belongs to.
  final String cardId;

  /// Number of consecutive successful reviews (resets to 0 on [ReviewGrade.again]).
  int repetition;

  /// FSRS memory stability — roughly: the number of days until retrievability
  /// drops to 90% from the last review. Grows with each successful review.
  double stability;

  /// FSRS difficulty in [1, 10]. Higher = harder. Updated after every review.
  double difficulty;

  /// When the card is next due for review.
  DateTime? nextReviewDate;

  /// When the card was last reviewed. Used to compute elapsed days.
  DateTime? lastReviewDate;

  FlashCardStat({
    required this.cardId,
    this.repetition = 0,
    this.stability = 0,
    this.difficulty = 0,
    this.nextReviewDate,
    this.lastReviewDate,
  });

  /// Creates a shallow copy — used by [FsrsService] to simulate future intervals
  /// without mutating the original stat.
  FlashCardStat.from(FlashCardStat other)
      : cardId = other.cardId,
        repetition = other.repetition,
        stability = other.stability,
        difficulty = other.difficulty,
        nextReviewDate = other.nextReviewDate,
        lastReviewDate = other.lastReviewDate;

  /// Days elapsed since the last review. Returns 0 for brand-new cards.
  int get elapsedDays {
    if (lastReviewDate == null) return 0;
    return DateTime.now().difference(lastReviewDate!).inDays;
  }

  /// Whether this card has never been reviewed before.
  bool get isNew => repetition == 0;
}
