import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:discere/learning/service/spaced_repetition_algorithm.dart';
import 'package:discere/learning/model/deck_stat.dart';
import 'package:discere/learning/model/flashcard_stat.dart';
import 'package:discere/learning/repository/flashcard_stat_repository.dart';
import 'package:discere/shared/service/notification_service.dart';
import 'package:discere/application/species_media/species_media_service.dart';

class FlashcardService {
  static final _log = Logger.forType(FlashcardService);
  final SpacedRepetitionAlgorithm _spacedRepetitionAlgorithm;
  final FlashcardStatRepository _flashcardStatRepository;
  final NotificationService notificationService;
  final SpeciesMediaService _speciesMediaService;

  const FlashcardService(
    this._spacedRepetitionAlgorithm,
    this._flashcardStatRepository,
    this.notificationService,
    this._speciesMediaService,
  );

  Future<List<SpeciesWithLocalImages>> getFlashCardsForReview(
    String deckId,
  ) async {
    final currentDate = DateTime.now();
    final List<FlashcardStat> statsForReview = await _flashcardStatRepository
        .getFlashcardStatsForReview(deckId, currentDate);

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

  Future<DeckStat> getDeckStat(String deckId) async {
    final stopwatch = Stopwatch()..start();
    final DeckStat deckStat = await _flashcardStatRepository.getDeckStat(
      deckId,
    );
    stopwatch.stop();
    _log.debug(
      'getDeckStat deck=$deckId '
      '(${stopwatch.elapsedMilliseconds}ms)',
    );
    return deckStat;
  }

  Future<void> initializeNextBatch(String deckId, {int batchSize = 10}) async {
    final Set<FlashcardStat> uninitializedStats = await _flashcardStatRepository
        .getUninitializedFlashcardStats(deckId, batchSize);

    for (var stat in uninitializedStats) {
      stat.nextReviewDate = DateTime.now();
    }

    await _flashcardStatRepository.insertOrUpdateFlashcardStats(
      uninitializedStats,
    );
  }

  Future<void> reviewCard(
    String speciesId,
    String deckId,
    ReviewGrade grade, {
    String? notificationTitle,
    String Function(int)? notificationBodyBuilder,
  }) async {
    FlashcardStat flashcardStat = await _getFlashcardStat(speciesId, deckId);

    flashcardStat = _spacedRepetitionAlgorithm.reviewCard(flashcardStat, grade);

    await _saveFlashcardStat(flashcardStat);
    await notificationService.requestPermissions();

    final allCards = await _flashcardStatRepository.getAllStats();
    await notificationService.rescheduleAll(
      cardDueDates: allCards.map((c) => c.nextReviewDate).toList(),
      preferredHour: 19,
      preferredMinute: 0,
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
    final stat = await _getFlashcardStat(speciesId, deckId);
    return _spacedRepetitionAlgorithm.previewIntervals(stat);
  }

  Future<List<SpeciesWithLocalImages>> _createFlashCards(
    Set<String> speciesIds,
  ) async {
    final ids = speciesIds.toList()..shuffle();

    final flashcards = await Future.wait(
      ids.map((id) => _speciesMediaService.resolveWithDownload(id)),
    );

    return flashcards.whereType<SpeciesWithLocalImages>().toList();
  }

  Future<FlashcardStat> _getFlashcardStat(
    String speciesId,
    String deckId,
  ) async {
    return await _flashcardStatRepository.getFlashcardStat(speciesId, deckId) ??
        FlashcardStat(speciesId: speciesId, deckId: deckId);
  }

  Future<void> _saveFlashcardStat(FlashcardStat flashcardStat) {
    return _flashcardStatRepository.insertOrUpdateFlashcardStats({
      flashcardStat,
    });
  }
}
