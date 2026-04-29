/// Per-deck configuration for the spaced repetition algorithm.
///
/// Created automatically with defaults when a deck is first accessed.
/// Stored in the `deck_config` table.
class DeckConfig {
  final String deckId;

  /// Target recall probability at review time (0.70–0.97).
  /// Higher values → shorter intervals → more reviews.
  final double desiredRetention;

  /// Maximum interval in days (~100 years default).
  final int maximumIntervalDays;

  /// Short-term learning steps for new cards, in minutes.
  /// Cards cycle through these before entering FSRS long-term scheduling.
  final List<Duration> learningSteps;

  /// Short-term re-learning steps after a lapse, in minutes.
  final List<Duration> relearningSteps;

  /// Maximum number of new cards to introduce per day (0 = unlimited).
  final int newCardsPerDay;

  /// Maximum number of review cards to show per day (0 = unlimited).
  final int maxReviewsPerDay;

  const DeckConfig({
    required this.deckId,
    this.desiredRetention = 0.9,
    this.maximumIntervalDays = 36500,
    this.learningSteps = const [Duration(minutes: 1), Duration(minutes: 10)],
    this.relearningSteps = const [Duration(minutes: 10)],
    this.newCardsPerDay = 20,
    this.maxReviewsPerDay = 200,
  });

  DeckConfig copyWith({
    String? deckId,
    double? desiredRetention,
    int? maximumIntervalDays,
    List<Duration>? learningSteps,
    List<Duration>? relearningSteps,
    int? newCardsPerDay,
    int? maxReviewsPerDay,
  }) {
    return DeckConfig(
      deckId: deckId ?? this.deckId,
      desiredRetention: desiredRetention ?? this.desiredRetention,
      maximumIntervalDays: maximumIntervalDays ?? this.maximumIntervalDays,
      learningSteps: learningSteps ?? this.learningSteps,
      relearningSteps: relearningSteps ?? this.relearningSteps,
      newCardsPerDay: newCardsPerDay ?? this.newCardsPerDay,
      maxReviewsPerDay: maxReviewsPerDay ?? this.maxReviewsPerDay,
    );
  }
}
