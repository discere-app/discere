/// How the user answers a flashcard during review.
enum ReviewMode {
  /// Tap to flip the card, then self-rate recall with the 4 FSRS buttons.
  flip,

  /// Pick the correct name from 4 options; graded automatically.
  multipleChoice;

  String get storageValue => name;

  static ReviewMode fromStorage(String? value) {
    return ReviewMode.values.firstWhere(
      (mode) => mode.storageValue == value,
      orElse: () => ReviewMode.flip,
    );
  }
}
