import 'package:discere/learning/model/flashcard_stat.dart';

/// The four review grades the user can give a card.
///
/// Displayed to the user as buttons. The UI should show the next interval
/// for each grade before the user taps.
enum ReviewGrade {
  again, // Forgot — show again very soon
  hard, // Remembered with significant difficulty
  good, // Remembered correctly
  easy, // Remembered effortlessly — push far out
}

/// Base interface for spaced repetition algorithms.
abstract class SpacedRepetitionAlgorithm {
  /// Record a review and return the updated [FlashcardStat].
  FlashcardStat reviewCard(FlashcardStat stat, ReviewGrade grade);

  /// Returns a preview of the next interval for each grade, in a
  /// user-friendly string (e.g. "10m", "1d", "2w").
  Map<ReviewGrade, String> previewIntervals(FlashcardStat stat);
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
