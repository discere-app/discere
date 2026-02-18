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
}
