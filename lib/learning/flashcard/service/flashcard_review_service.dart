import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/enrichment/media/service/species_media_service.dart';
import 'package:discere/learning/flashcard/repository/species_photo_gap_ack_repository.dart';
import 'package:discere/learning/flashcard/service/fsrs_service.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/learning/model/flashcard_stat.dart';
import 'package:discere/learning/model/learning_mode.dart';
import 'package:discere/learning/model/name_type.dart';
import 'package:discere/learning/repository/flashcard_stat_repository.dart';
import 'package:discere/shared/persistence/closed_database_tolerance.dart';
import 'package:discere/shared/util/logger.dart';

/// The live flashcard review engine for a [DeckPage] session: sourcing due
/// cards, FSRS grading, on-demand image resolution, and photo-gap tracking.
/// Split out of `FlashcardService`, which keeps only the deck
/// config/stat/notification surface shared with `decks/` and `app/` — every
/// method here is exercised exclusively from within `flashcard/`.
///
/// The deck's configuration is a parameter, not something this service looks
/// up. One session reads it once and hands the same value to every call, so
/// the learning mode a card was sourced for, the one its stats were written
/// under and the retention its intervals were computed with cannot disagree.
class FlashcardReviewService {
  static final _log = Logger.forType(FlashcardReviewService);

  final FlashcardStatRepository _flashcardStatRepository;
  final SpeciesMediaService _speciesMediaService;
  final SpeciesPhotoGapAckRepository _photoGapAckRepository;

  const FlashcardReviewService(
    this._flashcardStatRepository,
    this._speciesMediaService,
    this._photoGapAckRepository,
  );

  /// The algorithm [config] describes. Built per call rather than injected:
  /// it is a handful of numbers off the config, and deriving it here is what
  /// keeps a changed retention from needing anything rewired.
  FsrsService _algorithmFor(DeckConfig config) => FsrsService(
    requestRetention: config.desiredRetention,
    maximumIntervalDays: config.maximumIntervalDays.toDouble(),
    learningSteps: config.learningSteps,
    relearningSteps: config.relearningSteps,
  );

  Future<List<SpeciesWithLocalImages>> getFlashCardsForReview(
    String deckId,
    DeckConfig config,
  ) async {
    final currentDate = DateTime.now();
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

  Future<void> initializeNextBatch(
    String deckId,
    DeckConfig config, {
    int batchSize = 10,
  }) async {
    // A review session starts this without awaiting it.
    await runToleratingClosedDatabase(_log, () async {
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
    });
  }

  /// Grades a single card. Does not touch notification scheduling — callers
  /// reviewing multiple cards in a row (e.g. a review session) should call
  /// `FlashcardService.rescheduleNotifications` once after the session ends,
  /// not per card.
  Future<FlashcardStat> reviewCard(
    String speciesId,
    String deckId,
    DeckConfig config,
    ReviewGrade grade,
  ) async {
    FlashcardStat flashcardStat = await _getFlashcardStat(
      speciesId,
      deckId,
      config.learningMode,
      config.nameType,
    );
    final algorithm = _algorithmFor(config);

    flashcardStat = algorithm.reviewCard(flashcardStat, grade);

    await _saveFlashcardStat(flashcardStat);

    return flashcardStat;
  }

  /// Returns user-friendly interval strings for each grade.
  Future<Map<ReviewGrade, String>> getPreviewIntervals(
    String speciesId,
    String deckId,
    DeckConfig config,
  ) async {
    final stat = await _getFlashcardStat(
      speciesId,
      deckId,
      config.learningMode,
      config.nameType,
    );
    return _algorithmFor(config).previewIntervals(stat);
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
