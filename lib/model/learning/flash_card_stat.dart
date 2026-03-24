class FlashCardStat {
  final String speciesId;
  final String deckId;
  int interval;
  int repetition;
  double easeFactor;
  DateTime? nextReviewDate;

  FlashCardStat(
      {required this.speciesId,
      required this.deckId,
      this.interval = 1,
      this.repetition = 0,
      this.easeFactor = 2.5,
      this.nextReviewDate});

  FlashCardStat copyWith({
    String? speciesId,
    String? deckId,
    int? interval,
    int? repetition,
    double? easeFactor,
    DateTime? nextReviewDate,
  }) {
    return FlashCardStat(
      speciesId: speciesId ?? this.speciesId,
      deckId: deckId ?? this.deckId,
      interval: interval ?? this.interval,
      repetition: repetition ?? this.repetition,
      easeFactor: easeFactor ?? this.easeFactor,
      nextReviewDate: nextReviewDate ?? this.nextReviewDate,
    );
  }
}
