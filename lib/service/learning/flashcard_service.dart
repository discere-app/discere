import 'package:discere/service/learning/spaced_repetition_service.dart';

import '../../model/biology/species.dart';
import '../../model/biology/species_with_local_images.dart';
import '../../model/learning/deck_stat.dart';
import '../../model/learning/flash_card_stat.dart';
import '../../persistence/flash_card_stat_repository.dart';
import '../common/image_service.dart';
import '../../persistence/species_repository.dart';
import '../common/notification_service.dart';

class FlashCardService {
  final SpeciesRepository _speciesRepository;
  final ImageService _imageService;
  final SpacedRepetitionService _spacedRepetitionService;
  final FlashCardStatRepository _flashCardStatRepository;
  final NotificationService notificationService;

  FlashCardService(
    this._speciesRepository,
    this._imageService,
    this._spacedRepetitionService,
    this._flashCardStatRepository,
    this.notificationService,
  );

  Future<List<SpeciesWithLocalImages>> getFlashCardsForReview(
      String deckId) async {
    final currentDate = DateTime.now();
    final List<FlashCardStat> statsForReview = await _flashCardStatRepository
        .getFlashCardStatsForReview(deckId, currentDate);

    if (statsForReview.isEmpty) {
      DeckStat deckStat = await getDeckStat(deckId);
      // initialize first batch
      if (deckStat.uninitializedCount == deckStat.totalCount &&
          deckStat.totalCount > 0) {
        await initializeNextBatch(deckId);
        return getFlashCardsForReview(deckId);
      }
      // no cards to learn
      return [];
    }

    final Set<String> speciesIds =
        statsForReview.map((stat) => stat.speciesId).toSet();

    List<SpeciesWithLocalImages> flashCards =
        await _createFlashCards(speciesIds);
    flashCards.shuffle();
    return flashCards;
  }

  Future<List<SpeciesWithLocalImages>> getFlashCardsForSpecies(
      Set<String> species) async {
    return _createFlashCards(species);
  }

  Future<DeckStat> getDeckStat(String deckId) async {
    final DeckStat deckStat =
        await _flashCardStatRepository.getDeckStat(deckId);
    return deckStat;
  }

  Future<void> initializeNextBatch(String deckId, {int batchSize = 10}) async {
    final Set<FlashCardStat> uninitializedStats = await _flashCardStatRepository
        .getUninitializedFlashCardStats(deckId, batchSize);

    for (var stat in uninitializedStats) {
      stat.nextReviewDate = DateTime.now();
    }

    await _flashCardStatRepository
        .insertOrUpdateFlashCardStats(uninitializedStats);
  }

  void totalBlackout(String speciesId, String deckId) {
    _reviewFlashCard(speciesId, deckId, 0);
  }

  void incorrectButFamiliar(String speciesId, String deckId) {
    _reviewFlashCard(speciesId, deckId, 1);
  }

  void incorrectButNowIRemember(String speciesId, String deckId) {
    _reviewFlashCard(speciesId, deckId, 2);
  }

  void correctButDifficult(String speciesId, String deckId) {
    _reviewFlashCard(speciesId, deckId, 3);
  }

  void correctButNeededSomeTime(String speciesId, String deckId) {
    _reviewFlashCard(speciesId, deckId, 4);
  }

  void rateVeryEasy(String speciesId, String deckId) {
    _reviewFlashCard(speciesId, deckId, 5);
  }

  void _reviewFlashCard(String speciesId, String deckId, int quality) {
    FlashCardStat flashCardStat = _getFlashCardStat(speciesId, deckId);

    flashCardStat =
        _spacedRepetitionService.scheduleNextReview(flashCardStat, quality);

    _saveFlashCardStat(flashCardStat);
    _scheduleNotification(flashCardStat);
  }

  Future<List<SpeciesWithLocalImages>> _createFlashCards(
      Set<String> speciesIds) async {
    Set<Species> speciesList = await _speciesRepository.getSpecies(speciesIds);

    List<Future<SpeciesWithLocalImages>> flashcards =
        speciesList.map((species) async {
      List<String> localImagePaths =
          await _imageService.downloadAndSaveImages(species.images.toSet());
      return SpeciesWithLocalImages(species, localImagePaths);
    }).toList();

    flashcards.shuffle();

    return await Future.wait(flashcards);
  }

  FlashCardStat _getFlashCardStat(String speciesId, String deckId) {
    return FlashCardStat(
      speciesId: speciesId,
      deckId: deckId,
      nextReviewDate: DateTime.now(),
    );
  }

  void _saveFlashCardStat(FlashCardStat flashCardStat) {
    _flashCardStatRepository.insertOrUpdateFlashCardStats({flashCardStat});
  }

  Future<void> _scheduleNotification(FlashCardStat flashCardStat) async {
    notificationService.scheduleNotification(
        title: 'Zeit zum lernen',
        body: 'Deck: ${flashCardStat.deckId}',
        scheduledNotificationDateTime: flashCardStat.nextReviewDate!);
  }
}
