import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/enrichment/media/service/species_media_service.dart';
import 'package:discere/learning/flashcard/repository/species_photo_gap_ack_repository.dart';
import 'package:discere/learning/flashcard/service/fsrs_service.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/learning/model/flashcard_stat.dart';
import 'package:discere/learning/model/learning_mode.dart';
import 'package:discere/learning/model/name_type.dart';
import 'package:discere/learning/repository/deck_config_repository.dart';
import 'package:discere/learning/repository/flashcard_stat_repository.dart';
import 'package:discere/shared/service/user_preferences_service.dart';
import 'package:sqflite/sqflite.dart';

/// The live flashcard review engine for a [DeckPage] session: sourcing due
/// cards, FSRS grading, on-demand image resolution, and photo-gap tracking.
/// Split out of `FlashcardService`, which keeps only the deck
/// config/stat/notification surface shared with `decks/` and `app/` — every
/// method here is exercised exclusively from within `flashcard/`.
class FlashcardReviewService {
  final FsrsService _defaultAlgorithm;
  final FlashcardStatRepository _flashcardStatRepository;
  final SpeciesMediaService _speciesMediaService;
  final SpeciesPhotoGapAckRepository _photoGapAckRepository;
  final DeckConfigRepository? _deckConfigRepository;
  final UserPreferencesService? _userPreferencesService;

  const FlashcardReviewService(
    this._defaultAlgorithm,
    this._flashcardStatRepository,
    this._speciesMediaService,
    this._photoGapAckRepository, {
    DeckConfigRepository? deckConfigRepository,
    UserPreferencesService? userPreferencesService,
  }) : _deckConfigRepository = deckConfigRepository,
       _userPreferencesService = userPreferencesService;

  double get _globalDefaultRetention =>
      _userPreferencesService?.defaultDesiredRetention ?? 0.9;

  /// Returns the current DeckConfig for [deckId], or defaults — a private
  /// copy of `FlashcardService.getDeckConfig`'s same repository-with-fallback
  /// logic, kept local so this service doesn't need to depend on the other.
  Future<DeckConfig> _getDeckConfig(String deckId) async {
    return _deckConfigRepository?.getOrDefault(
          deckId,
          defaultRetention: _globalDefaultRetention,
        ) ??
        Future.value(
          DeckConfig(deckId: deckId, desiredRetention: _globalDefaultRetention),
        );
  }

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
    final config = await _getDeckConfig(deckId);
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

    final flashCards = await getFlashCardsForSpecies(speciesIds);
    flashCards.shuffle();
    return flashCards;
  }

  /// Resolves [species] into cards in one bundled pass — the whole set costs
  /// a fixed number of queries, so a session's load time does not grow with
  /// the number of due cards.
  Future<List<SpeciesWithLocalImages>> getFlashCardsForSpecies(
    Set<String> species,
  ) {
    return _speciesMediaService.resolveAllFromCache(species);
  }

  /// Species in [speciesIds] that still have no local picture at all and
  /// haven't already been acknowledged (via [acknowledgePhotoGaps]) for
  /// [deckId] — i.e. species the "no photo found" gaps dialog should still
  /// ask about. Relying on what is on disk here is safe precisely because
  /// callers only invoke this once a deck's image-enrichment stages are
  /// complete (see [DeckSessionPresenter.filterReviewableCards]'s doc for the
  /// same invariant): at that point a missing picture file means both the
  /// reference image and the iNaturalist lookup were tried and came up empty,
  /// not just "not downloaded yet".
  ///
  /// Two phases, because the two questions cost very different amounts. Which
  /// species have a gap is decided from the candidate image URLs alone
  /// ([SpeciesMediaService.findSpeciesWithoutLocalImage]); only the gaps are
  /// then loaded as full cards, because that is what the dialog needs them for
  /// — a display name, and therefore common names and classification. Resolving
  /// the whole deck that way would pay the full taxonomy load for every species
  /// just to throw all but a handful away.
  ///
  /// The acknowledged species are subtracted first rather than filtered out
  /// afterwards: this runs alongside the first card of a session and shares its
  /// database connection, so species the dialog can no longer ask about are not
  /// worth examining.
  Future<List<SpeciesWithLocalImages>> getUnacknowledgedPhotoGaps(
    String deckId,
    Set<String> speciesIds,
  ) async {
    final acknowledged = await _photoGapAckRepository
        .getAcknowledgedSpeciesIds(deckId);
    final candidates = speciesIds.difference(acknowledged);
    if (candidates.isEmpty) return const [];

    final gaps = await _speciesMediaService.findSpeciesWithoutLocalImage(
      candidates,
    );
    if (gaps.isEmpty) return const [];
    return getFlashCardsForSpecies(gaps);
  }

  Future<void> acknowledgePhotoGaps(String deckId, Set<String> speciesIds) =>
      _photoGapAckRepository.acknowledge(deckId, speciesIds);

  Future<SpeciesWithLocalImages?> ensureSingleImageForSpecies(
    String speciesId,
  ) {
    return _speciesMediaService.resolveEnsuringSingleImage(speciesId);
  }

  Future<void> initializeNextBatch(String deckId, {int batchSize = 10}) async {
    try {
      final config = await _getDeckConfig(deckId);
      await _flashcardStatRepository.ensureStatsForLearningMode(
        deckId,
        config.learningMode,
        config.nameType,
      );

      final Set<FlashcardStat> uninitializedStats =
          await _flashcardStatRepository.getUninitializedFlashcardStats(
            deckId,
            batchSize,
            config.learningMode,
            config.nameType,
          );

      final now = DateTime.now();
      await _flashcardStatRepository.insertOrUpdateFlashcardStats({
        for (final stat in uninitializedStats)
          stat.copyWith(nextReviewDate: now),
      });
    } on DatabaseException {
      // Same reasoning as DeckSessionService's other fire-and-forget calls -
      // this is invoked without awaiting from DeckPage, so a closed DB
      // mid-flight means the batch init is simply moot now.
    }
  }

  /// Grades a single card. Does not touch notification scheduling — callers
  /// reviewing multiple cards in a row (e.g. a review session) should call
  /// `FlashcardService.rescheduleNotifications` once after the session ends,
  /// not per card.
  Future<FlashcardStat> reviewCard(
    String speciesId,
    String deckId,
    ReviewGrade grade,
  ) async {
    final config = await _getDeckConfig(deckId);
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

  /// Returns user-friendly interval strings for each grade.
  Future<Map<ReviewGrade, String>> getPreviewIntervals(
    String speciesId,
    String deckId,
  ) async {
    final config = await _getDeckConfig(deckId);
    final stat = await _getFlashcardStat(
      speciesId,
      deckId,
      config.learningMode,
      config.nameType,
    );
    final algorithm = await _algorithmFor(deckId);
    return algorithm.previewIntervals(stat);
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
