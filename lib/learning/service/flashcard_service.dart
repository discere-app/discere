import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/learning/repository/daily_count_repository.dart';
import 'package:discere/learning/repository/deck_config_repository.dart';
import 'package:discere/learning/service/fsrs_service.dart';
import 'package:discere/learning/model/deck_stat.dart';
import 'package:discere/learning/model/flashcard_stat.dart';
import 'package:discere/learning/repository/flashcard_stat_repository.dart';
import 'package:discere/shared/service/notification_service.dart';
import 'package:discere/shared/service/user_preferences_service.dart';
import 'package:discere/application/species_media/species_media_service.dart';

class FlashcardService {
  static final _log = Logger.forType(FlashcardService);
  final FsrsService _defaultAlgorithm;
  final FlashcardStatRepository _flashcardStatRepository;
  final NotificationService notificationService;
  final SpeciesMediaService _speciesMediaService;
  final DeckConfigRepository? _deckConfigRepository;
  final DailyCountRepository? _dailyCountRepository;
  final UserPreferencesService? _userPreferencesService;

  const FlashcardService(
    this._defaultAlgorithm,
    this._flashcardStatRepository,
    this.notificationService,
    this._speciesMediaService, {
    DeckConfigRepository? deckConfigRepository,
    DailyCountRepository? dailyCountRepository,
    UserPreferencesService? userPreferencesService,
  }) : _deckConfigRepository = deckConfigRepository,
       _dailyCountRepository = dailyCountRepository,
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
    );
    final List<FlashcardStat> statsForReview = await _flashcardStatRepository
        .getFlashcardStatsForReview(deckId, currentDate, config.learningMode);

    if (statsForReview.isEmpty) {
      return [];
    }

    // Apply daily review limit: Learning/Relearning cards always shown;
    // Review cards are capped by maxReviewsPerDay.
    final List<FlashcardStat> filteredStats;
    if (_deckConfigRepository != null && _dailyCountRepository != null) {
      if (config.maxReviewsPerDay > 0) {
        final todayReviewCount = await _dailyCountRepository
            .getTodayReviewCount(deckId, learningMode: config.learningMode);
        final reviewBudget = (config.maxReviewsPerDay - todayReviewCount).clamp(
          0,
          config.maxReviewsPerDay,
        );

        int reviewsIncluded = 0;
        filteredStats = [];
        for (final stat in statsForReview) {
          if (stat.cardState == CardState.learning ||
              stat.cardState == CardState.relearning) {
            filteredStats.add(stat);
          } else if (reviewsIncluded < reviewBudget) {
            filteredStats.add(stat);
            reviewsIncluded++;
          }
        }
      } else {
        filteredStats = statsForReview;
      }
    } else {
      filteredStats = statsForReview;
    }

    if (filteredStats.isEmpty) {
      return [];
    }

    final Set<String> speciesIds = filteredStats
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
    final config = await getDeckConfig(deckId);
    await _flashcardStatRepository.ensureStatsForLearningMode(
      deckId,
      config.learningMode,
    );
    final stopwatch = Stopwatch()..start();
    final DeckStat baseStat = await _flashcardStatRepository.getDeckStat(
      deckId,
      learningMode: config.learningMode,
    );
    stopwatch.stop();
    _log.debug(
      'getDeckStat deck=$deckId '
      '(${stopwatch.elapsedMilliseconds}ms)',
    );

    if (_dailyCountRepository == null) return baseStat;

    final todayNewCount = await _dailyCountRepository.getTodayNewCount(
      deckId,
      learningMode: config.learningMode,
    );
    final todayReviewCount = await _dailyCountRepository.getTodayReviewCount(
      deckId,
      learningMode: config.learningMode,
    );

    return DeckStat(
      baseStat.totalCount,
      baseStat.uninitializedCount,
      baseStat.dueCount,
      todayNewCount: todayNewCount,
      todayReviewCount: todayReviewCount,
    );
  }

  Future<void> initializeNextBatch(String deckId, {int batchSize = 10}) async {
    final config = await getDeckConfig(deckId);
    await _flashcardStatRepository.ensureStatsForLearningMode(
      deckId,
      config.learningMode,
    );
    // Respect newCardsPerDay limit if configured.
    final effectiveBatchSize = await _effectiveNewBatchSize(
      deckId,
      batchSize,
      config,
    );
    if (effectiveBatchSize <= 0) return;

    final Set<FlashcardStat> uninitializedStats = await _flashcardStatRepository
        .getUninitializedFlashcardStats(
          deckId,
          effectiveBatchSize,
          config.learningMode,
        );

    for (var stat in uninitializedStats) {
      stat.nextReviewDate = DateTime.now();
    }

    await _flashcardStatRepository.insertOrUpdateFlashcardStats(
      uninitializedStats,
    );
  }

  Future<int> _effectiveNewBatchSize(
    String deckId,
    int requested,
    DeckConfig config,
  ) async {
    if (_deckConfigRepository == null || _dailyCountRepository == null) {
      return requested;
    }
    if (config.newCardsPerDay <= 0) return requested;
    final todayNewCount = await _dailyCountRepository.getTodayNewCount(
      deckId,
      learningMode: config.learningMode,
    );
    final budget = config.newCardsPerDay - todayNewCount;
    return budget.clamp(0, requested);
  }

  Future<FlashcardStat> reviewCard(
    String speciesId,
    String deckId,
    ReviewGrade grade, {
    String? notificationTitle,
    String Function(int)? notificationBodyBuilder,
  }) async {
    final config = await getDeckConfig(deckId);
    FlashcardStat flashcardStat = await _getFlashcardStat(
      speciesId,
      deckId,
      config.learningMode,
    );
    final stateBeforeReview = flashcardStat.cardState;
    final algorithm = await _algorithmFor(deckId);

    flashcardStat = algorithm.reviewCard(flashcardStat, grade);

    // Track daily counts based on state BEFORE the review.
    if (_dailyCountRepository != null) {
      if (stateBeforeReview == CardState.newCard) {
        await _dailyCountRepository.incrementNewCount(
          deckId,
          learningMode: config.learningMode,
        );
      } else if (stateBeforeReview == CardState.review) {
        await _dailyCountRepository.incrementReviewCount(
          deckId,
          learningMode: config.learningMode,
        );
      }
    }

    await _saveFlashcardStat(flashcardStat);
    await notificationService.requestPermissions();

    await rescheduleNotifications(
      notificationTitle: notificationTitle,
      notificationBodyBuilder: notificationBodyBuilder,
    );

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
    final allCards = await _flashcardStatRepository.getAllStats();
    await notificationService.rescheduleAll(
      cardDueDates: allCards.map((c) => c.nextReviewDate).toList(),
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
    );
    final algorithm = await _algorithmFor(deckId);
    return algorithm.previewIntervals(stat);
  }

  /// Loads, updates, and persists the DeckConfig for [deckId].
  Future<void> saveDeckConfig(DeckConfig config) async {
    _deckConfigRepository?.save(config);
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

    final flashcards = await Future.wait(
      ids.map((id) => _speciesMediaService.resolveFromCache(id)),
    );

    return flashcards.whereType<SpeciesWithLocalImages>().toList();
  }

  Future<FlashcardStat> _getFlashcardStat(
    String speciesId,
    String deckId,
    LearningMode learningMode,
  ) async {
    return await _flashcardStatRepository.getFlashcardStat(
          speciesId,
          deckId,
          learningMode,
        ) ??
        FlashcardStat(
          speciesId: speciesId,
          deckId: deckId,
          learningMode: learningMode,
        );
  }

  Future<void> _saveFlashcardStat(FlashcardStat flashcardStat) {
    return _flashcardStatRepository.insertOrUpdateFlashcardStats({
      flashcardStat,
    });
  }
}
