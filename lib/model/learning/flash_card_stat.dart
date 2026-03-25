class FlashCardStat {
  final String speciesId;
  final String deckId;
  
  // SM-2 fields
  int interval;
  int repetition;
  double easeFactor;
  
  // FSRS fields
  double stability;
  double difficulty;
  DateTime? lastReviewDate;
  
  // Common field
  DateTime? nextReviewDate;

  FlashCardStat({
    required this.speciesId,
    required this.deckId,
    this.interval = 1,
    this.repetition = 0,
    this.easeFactor = 2.5,
    this.stability = 0.0,
    this.difficulty = 0.0,
    this.lastReviewDate,
    this.nextReviewDate,
  });

  /// True only if this card has never been reviewed.
  bool get isNew => lastReviewDate == null;

  int get elapsedDays =>
      lastReviewDate == null ? 0 : DateTime.now().difference(lastReviewDate!).inDays;

  FlashCardStat copyWith({
    String? speciesId,
    String? deckId,
    int? interval,
    int? repetition,
    double? easeFactor,
    double? stability,
    double? difficulty,
    DateTime? lastReviewDate,
    DateTime? nextReviewDate,
  }) {
    return FlashCardStat(
      speciesId: speciesId ?? this.speciesId,
      deckId: deckId ?? this.deckId,
      interval: interval ?? this.interval,
      repetition: repetition ?? this.repetition,
      easeFactor: easeFactor ?? this.easeFactor,
      stability: stability ?? this.stability,
      difficulty: difficulty ?? this.difficulty,
      lastReviewDate: lastReviewDate ?? this.lastReviewDate,
      nextReviewDate: nextReviewDate ?? this.nextReviewDate,
    );
  }

  /// Create a clone from an existing instance
  factory FlashCardStat.from(FlashCardStat stat) {
    return stat.copyWith();
  }
}
