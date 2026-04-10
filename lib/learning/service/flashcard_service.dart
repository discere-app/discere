import 'package:flutter/foundation.dart';

import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/learning/service/spaced_repetition_algorithm.dart';
import 'package:discere/learning/model/deck_stat.dart';
import 'package:discere/learning/model/flash_card_stat.dart';
import 'package:discere/learning/repository/flash_card_stat_repository.dart';
import 'package:discere/enrichment/repository/inat_photo_cache_repository.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/shared/service/notification_service.dart';
import 'package:discere/catalog/service/species_image_service.dart';

class FlashCardService {
  final SpeciesRepository _speciesRepository;
  final SpacedRepetitionAlgorithm _spacedRepetitionAlgorithm;
  final FlashCardStatRepository _flashCardStatRepository;
  final NotificationService notificationService;
  final SpeciesImageService _speciesImageService;

  FlashCardService(
    this._speciesRepository,
    ImageService imageService,
    this._spacedRepetitionAlgorithm,
    this._flashCardStatRepository,
    this.notificationService,
    INatPhotoCacheRepository iNatCacheRepository, {
    SpeciesImageService? speciesImageService,
  }) : _speciesImageService =
           speciesImageService ??
           SpeciesImageService(imageService, iNatCacheRepository);

  Future<List<SpeciesWithLocalImages>> getFlashCardsForReview(
    String deckId,
  ) async {
    final currentDate = DateTime.now();
    final List<FlashCardStat> statsForReview = await _flashCardStatRepository
        .getFlashCardStatsForReview(deckId, currentDate);

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
    final DeckStat deckStat = await _flashCardStatRepository.getDeckStat(
      deckId,
    );
    stopwatch.stop();
    if (kDebugMode) {
      debugPrint(
        'FlashCardService: getDeckStat deck=$deckId '
        '(${stopwatch.elapsedMilliseconds}ms)',
      );
    }
    return deckStat;
  }

  Future<void> initializeNextBatch(String deckId, {int batchSize = 10}) async {
    final Set<FlashCardStat> uninitializedStats = await _flashCardStatRepository
        .getUninitializedFlashCardStats(deckId, batchSize);

    for (var stat in uninitializedStats) {
      stat.nextReviewDate = DateTime.now();
    }

    await _flashCardStatRepository.insertOrUpdateFlashCardStats(
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
    FlashCardStat flashCardStat = await _getFlashCardStat(speciesId, deckId);

    flashCardStat = _spacedRepetitionAlgorithm.reviewCard(flashCardStat, grade);

    await _saveFlashCardStat(flashCardStat);
    await notificationService.requestPermissions();

    final allCards = await _flashCardStatRepository.getAllStats();
    await notificationService.rescheduleAll(
      allCards: allCards,
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
    final stat = await _getFlashCardStat(speciesId, deckId);
    return _spacedRepetitionAlgorithm.previewIntervals(stat);
  }

  Future<List<SpeciesWithLocalImages>> _createFlashCards(
    Set<String> speciesIds,
  ) async {
    Set<Species> speciesList = await _speciesRepository.getSpecies(speciesIds);

    List<Future<SpeciesWithLocalImages>> flashcards = speciesList.map((
      species,
    ) async {
      return _speciesImageService.getSpeciesWithLocalImages(
        species,
        downloadMissing: true,
      );
    }).toList();

    flashcards.shuffle();

    return await Future.wait(flashcards);
  }

  Future<FlashCardStat> _getFlashCardStat(
    String speciesId,
    String deckId,
  ) async {
    return await _flashCardStatRepository.getFlashCardStat(speciesId, deckId) ??
        FlashCardStat(speciesId: speciesId, deckId: deckId);
  }

  Future<void> _saveFlashCardStat(FlashCardStat flashCardStat) {
    return _flashCardStatRepository.insertOrUpdateFlashCardStats({
      flashCardStat,
    });
  }
}
