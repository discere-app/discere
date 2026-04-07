import 'package:flutter/foundation.dart';

import 'spaced_repetition_algorithm.dart';
import '../../model/biology/picture.dart';
import '../../model/biology/species.dart';
import '../../model/biology/species_with_local_images.dart';
import '../../model/learning/deck_stat.dart';
import '../../model/learning/flash_card_stat.dart';
import '../../persistence/flash_card_stat_repository.dart';
import '../../persistence/inat_photo_cache_repository.dart';
import '../common/image_service.dart';
import '../../persistence/species_repository.dart';
import '../common/notification_service.dart';

class FlashCardService {
  final SpeciesRepository _speciesRepository;
  final ImageService _imageService;
  final SpacedRepetitionAlgorithm _spacedRepetitionAlgorithm;
  final FlashCardStatRepository _flashCardStatRepository;
  final NotificationService notificationService;
  final INatPhotoCacheRepository _iNatCacheRepository;

  FlashCardService(
    this._speciesRepository,
    this._imageService,
    this._spacedRepetitionAlgorithm,
    this._flashCardStatRepository,
    this.notificationService,
    this._iNatCacheRepository,
  );

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
      // Use reference pictures + any already-cached iNat photos.
      final allPictures = await _withCachedINatPhotos(species);

      final urlsToDownload = allPictures
          .map((p) => p.url)
          .where((url) => url != null && url.isNotEmpty)
          .cast<String>()
          .toSet();

      final urlToLocalPath = await _imageService.downloadAndSaveImagesMap(
        urlsToDownload,
      );

      final localPictures = allPictures
          .map((p) {
            if (p.url != null && urlToLocalPath.containsKey(p.url)) {
              return LocalPicture(p, urlToLocalPath[p.url]!);
            }
            return null;
          })
          .whereType<LocalPicture>()
          .toList();

      return SpeciesWithLocalImages(species, localPictures);
    }).toList();

    flashcards.shuffle();

    return await Future.wait(flashcards);
  }

  /// Reads already-cached iNat photos from local DB (no API call).
  Future<List<Picture>> _withCachedINatPhotos(Species species) async {
    final refPictures = List<Picture>.from(species.pictures);

    try {
      final cached = await _iNatCacheRepository.getCachedPhotos(species.id);
      if (cached != null && cached.isNotEmpty) {
        return [...refPictures, ...cached];
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('iNat cache read failed for ${species.id}: $e');
      }
    }

    return refPictures;
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
