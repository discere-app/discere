import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/learning/model/deck_stat.dart';
import 'package:discere/learning/repository/deck_config_repository.dart';
import 'package:discere/learning/repository/flashcard_stat_repository.dart';
import 'package:discere/shared/service/notification_service.dart';
import 'package:discere/shared/service/user_preferences_service.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:sqflite/sqflite.dart';

/// The deck-level config/progress/notification surface shared across
/// `decks/`, `app/`, and `flashcard/` — everything about a deck's flashcard
/// learning *settings* and *progress summary*, as opposed to actively
/// reviewing a card, which lives in `flashcard/flashcard_review_service.dart`
/// (`FlashcardReviewService`).
class FlashcardService {
  static final _log = Logger.forType(FlashcardService);
  final FlashcardStatRepository _flashcardStatRepository;
  final NotificationService _notificationService;
  final DeckConfigRepository? _deckConfigRepository;
  final UserPreferencesService? _userPreferencesService;

  const FlashcardService(
    this._flashcardStatRepository,
    this._notificationService, {
    DeckConfigRepository? deckConfigRepository,
    UserPreferencesService? userPreferencesService,
  }) : _deckConfigRepository = deckConfigRepository,
       _userPreferencesService = userPreferencesService;

  double get _globalDefaultRetention =>
      _userPreferencesService?.defaultDesiredRetention ?? 0.9;

  Future<DeckStat> getDeckStat(String deckId) async {
    try {
      final config = await getDeckConfig(deckId);
      await _flashcardStatRepository.ensureStatsForLearningMode(
        deckId,
        config.learningMode,
        config.nameType,
      );
      final stopwatch = Stopwatch()..start();
      final DeckStat deckStat = await _flashcardStatRepository.getDeckStat(
        deckId,
        learningMode: config.learningMode,
        nameType: config.nameType,
      );
      stopwatch.stop();
      _log.debug(
        'getDeckStat deck=$deckId '
        '(${stopwatch.elapsedMilliseconds}ms)',
      );

      return deckStat;
    } on DatabaseException {
      // The user DB was closed while this was in flight (app shutdown, or -
      // in integration tests - the next test's teardown deleting the DB out
      // from under a caller that doesn't await this, e.g. a grading/continue
      // button handler). Nothing meaningful to report, so degrade to "empty"
      // instead of throwing.
      return DeckStat(0, 0, 0);
    }
  }

  int get _notificationHour => _userPreferencesService?.notificationHour ?? 19;

  int get _notificationMinute =>
      _userPreferencesService?.notificationMinute ?? 0;

  /// Recomputes and reschedules all pending daily review notifications,
  /// e.g. after the user changes the preferred notification time.
  Future<void> rescheduleNotifications({
    String? notificationTitle,
    String Function(int count)? notificationBodyBuilder,
  }) async {
    try {
      final nextReviewDates = await _flashcardStatRepository
          .getAllNextReviewDates();
      await _notificationService.rescheduleAll(
        cardDueDates: nextReviewDates,
        preferredHour: _notificationHour,
        preferredMinute: _notificationMinute,
        daysAhead: 14,
        title: notificationTitle ?? 'Zeit zum Üben',
        bodyBuilder:
            notificationBodyBuilder ??
            (count) => 'Du hast $count Karten zum Wiederholen.',
      );
    } on DatabaseException {
      // The user DB was closed while this was in flight (app shutdown, or -
      // in integration tests - the next test's teardown deleting the DB out
      // from under DeckPage.dispose()'s unawaited call to this). Nothing
      // left to reschedule against.
    }
  }

  /// Loads, updates, and persists the DeckConfig for [deckId].
  Future<void> saveDeckConfig(DeckConfig config) async {
    await _deckConfigRepository?.save(config);
  }

  /// Returns the current DeckConfig for [deckId], or defaults.
  Future<DeckConfig> getDeckConfig(String deckId) async {
    return _deckConfigRepository?.getOrDefault(
          deckId,
          defaultRetention: _globalDefaultRetention,
        ) ??
        Future.value(
          DeckConfig(deckId: deckId, desiredRetention: _globalDefaultRetention),
        );
  }
}
