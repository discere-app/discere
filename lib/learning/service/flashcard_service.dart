import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/enrichment/service/species_media_service.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/learning/model/deck_stat.dart';
import 'package:discere/learning/model/flashcard_stat.dart';
import 'package:discere/learning/repository/deck_config_repository.dart';
import 'package:discere/learning/repository/flashcard_stat_repository.dart';
import 'package:discere/learning/service/fsrs_service.dart';
import 'package:discere/shared/service/notification_service.dart';
import 'package:discere/shared/service/user_preferences_service.dart';
import 'package:discere/shared/util/concurrency_utils.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:sqflite/sqflite.dart';

class FlashcardService {
  static final _log = Logger.forType(FlashcardService);
  static const _maxConcurrentCacheReads = 10;
  final FsrsService _defaultAlgorithm;
  final FlashcardStatRepository _flashcardStatRepository;
  final NotificationService notificationService;
  final SpeciesMediaService _speciesMediaService;
  final DeckConfigRepository? _deckConfigRepository;
  final UserPreferencesService? _userPreferencesService;

  const FlashcardService(
    this._defaultAlgorithm,
    this._flashcardStatRepository,
    this.notificationService,
    this._speciesMediaService, {
    DeckConfigRepository? deckConfigRepository,
    UserPreferencesService? userPreferencesService,
  }) : _deckConfigRepository = deckConfigRepository,
       _userPreferencesService = userPreferencesService;

  double get _globalDefaultRetention =>
      _userPreferencesService?.defaultDesiredRetention ?? 0.9;

  /// Returns a per-deck algorithm instance if [DeckConfigRepository] is
  /// available, otherwise falls back to the default algorithm.
  Future<FsrsService> _algorithmFor(String deckId) async {
    if (_deckConfigRepository == null) return _defaultAlgorithm;
    final config = await _deckConfigRepository.getOrDefault(
      deckId,
      defaultRetention: _globalDefaultRetention,
    );
    return FsrsService(
      requestRetention: config.desiredRetention,
      maximumIntervalDays: config.maximumIntervalDays.toDouble(),
      learningSteps: config.learningSteps,
      relearningSteps: config.relearningSteps,
    );
  }

  Future<List<SpeciesWithLocalImages>> getFlashCardsForReview(
    String deckId,
  ) async {
    final currentDate = DateTime.now();
    final config = await getDeckConfig(deckId);
    await _flashcardStatRepository.ensureStatsForLearningMode(
      deckId,
      config.learningMode,
      config.nameType,
    );
    final List<FlashcardStat> statsForReview = await _flashcardStatRepository
        .getFlashcardStatsForReview(
          deckId,
          currentDate,
          config.learningMode,
          config.nameType,
        );

    if (statsForReview.isEmpty) {
      return [];
    }

    final Set<String> speciesIds = statsForReview
        .map((stat) => stat.speciesId)
        .toSet();

    List<SpeciesWithLocalImages> flashCards = await _createFlashCards(
      speciesIds,
    );
    flashCards.shuffle();
    return flashCards;
  }

  Future<List<SpeciesWithLocalImages>> getFlashCardsForSpecies(
    Set<String> species,
  ) async {
    return _createFlashCards(species);
  }

  Future<SpeciesWithLocalImages?> ensureSingleImageForSpecies(
    String speciesId,
  ) {
    return _speciesMediaService.resolveEnsuringSingleImage(speciesId);
  }

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

  Future<void> initializeNextBatch(String deckId, {int batchSize = 10}) async {
    try {
      final config = await getDeckConfig(deckId);
      await _flashcardStatRepository.ensureStatsForLearningMode(
        deckId,
        config.learningMode,
        config.nameType,
      );

      final Set<FlashcardStat> uninitializedStats = await _flashcardStatRepository
          .getUninitializedFlashcardStats(
            deckId,
            batchSize,
            config.learningMode,
            config.nameType,
          );

      for (var stat in uninitializedStats) {
        stat.nextReviewDate = DateTime.now();
      }

      await _flashcardStatRepository.insertOrUpdateFlashcardStats(
        uninitializedStats,
      );
    } on DatabaseException {
      // Same reasoning as getDeckStat above - this is invoked fire-and-forget
      // from DeckPage, so a closed DB mid-flight means the batch init is
      // simply moot now.
    }
  }

  /// Grades a single card. Does not touch notification scheduling — callers
  /// reviewing multiple cards in a row (e.g. a review session) should call
  /// [rescheduleNotifications] once after the session ends, not per card.
  Future<FlashcardStat> reviewCard(
    String speciesId,
    String deckId,
    ReviewGrade grade,
  ) async {
    final config = await getDeckConfig(deckId);
    FlashcardStat flashcardStat = await _getFlashcardStat(
      speciesId,
      deckId,
      config.learningMode,
      config.nameType,
    );
    final algorithm = await _algorithmFor(deckId);

    flashcardStat = algorithm.reviewCard(flashcardStat, grade);

    await _saveFlashcardStat(flashcardStat);

    return flashcardStat;
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
    final nextReviewDates = await _flashcardStatRepository
        .getAllNextReviewDates();
    await notificationService.rescheduleAll(
      cardDueDates: nextReviewDates,
      preferredHour: _notificationHour,
      preferredMinute: _notificationMinute,
      daysAhead: 14,
      title: notificationTitle ?? 'Zeit zum Üben',
      bodyBuilder:
          notificationBodyBuilder ??
          (count) => 'Du hast $count Karten zum Wiederholen.',
    );
  }

  /// Returns user-friendly interval strings for each grade.
  Future<Map<ReviewGrade, String>> getPreviewIntervals(
    String speciesId,
    String deckId,
  ) async {
    final config = await getDeckConfig(deckId);
    final stat = await _getFlashcardStat(
      speciesId,
      deckId,
      config.learningMode,
      config.nameType,
    );
    final algorithm = await _algorithmFor(deckId);
    return algorithm.previewIntervals(stat);
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

  Future<List<SpeciesWithLocalImages>> _createFlashCards(
    Set<String> speciesIds,
  ) async {
    final ids = speciesIds.toList()..shuffle();

    final flashcards = await runWithConcurrency<String, SpeciesWithLocalImages?>(
      ids,
      maxConcurrent: _maxConcurrentCacheReads,
      task: _speciesMediaService.resolveFromCache,
    );

    return flashcards.whereType<SpeciesWithLocalImages>().toList();
  }

  Future<FlashcardStat> _getFlashcardStat(
    String speciesId,
    String deckId,
    LearningMode learningMode,
    NameType nameType,
  ) async {
    return await _flashcardStatRepository.getFlashcardStat(
          speciesId,
          deckId,
          learningMode,
          nameType,
        ) ??
        FlashcardStat(
          speciesId: speciesId,
          deckId: deckId,
          learningMode: learningMode,
          nameType: nameType,
        );
  }

  Future<void> _saveFlashcardStat(FlashcardStat flashcardStat) {
    return _flashcardStatRepository.insertOrUpdateFlashcardStats({
      flashcardStat,
    });
  }
}
