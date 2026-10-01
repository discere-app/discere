import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/learning/flashcard/deck_session_presenter.dart';
import 'package:discere/learning/flashcard/service/flashcard_review_service.dart';
import 'package:discere/learning/flashcard/service/fsrs_service.dart';
import 'package:discere/learning/flashcard/service/multiple_choice_distractor_pool_service.dart';
import 'package:discere/learning/flashcard/service/taxonomy_distractor_pools.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/learning/model/flashcard_stat.dart';
import 'package:discere/learning/model/learning_mode.dart';
import 'package:discere/learning/model/name_type.dart';
import 'package:discere/learning/model/review_mode.dart';
import 'package:discere/learning/service/decks_service.dart';

/// Everything [DeckSessionService.loadSessionData] fetches to (re)start a
/// review session for a given [DeckConfig] — bundles several independent
/// async lookups (deck species, due cards, image-wait state,
/// pending-common-name state) that [DeckPageState] previously performed
/// directly, one after another, into a single call.
class DeckSessionData {
  final List<SpeciesWithLocalImages> reviewableCards;
  final bool isWaitingForImages;
  final List<SpeciesWithLocalImages> awaitingImageCards;
  final Set<String> pendingCommonNameSpeciesIds;

  /// Where a card's multiple-choice distractors come from, or `null` outside
  /// multiple-choice mode. The pools themselves are built per card scope on
  /// demand, so this is a handle to the session's pools rather than the pools
  /// themselves.
  final TaxonomyDistractorPools? distractorPools;

  const DeckSessionData({
    required this.reviewableCards,
    required this.isWaitingForImages,
    required this.awaitingImageCards,
    required this.pendingCommonNameSpeciesIds,
    required this.distractorPools,
  });
}

/// The outcome of grading one card: its resulting [CardState], and whether
/// it needs to be requeued for relearning within this same session (see
/// [DeckSessionPresenter.shouldRequeue]).
class CardGradeResult {
  final CardState cardState;
  final bool shouldRequeue;

  const CardGradeResult({
    required this.cardState,
    required this.shouldRequeue,
  });
}

/// Non-UI orchestration for a [DeckPage] review session: composes
/// [FlashcardReviewService], [DecksService], [INatEnrichmentQueueService] and
/// [MultipleChoiceDistractorPoolService] into the coarse operations a
/// session actually needs. Holds no BuildContext/State coupling — pure async
/// data orchestration. `DeckPageState` keeps everything that touches
/// `setState`/`mounted`/dialogs/`context.loc` itself (see CLAUDE.md's
/// widget-organization guidance for that split).
class DeckSessionService {
  final FlashcardReviewService _flashcardReviewService;
  final DecksService _decksService;
  final INatEnrichmentQueueService _enrichmentQueueService;
  final MultipleChoiceDistractorPoolService _distractorPoolService;
  final DeckSessionPresenter _sessionPresenter;

  const DeckSessionService({
    required FlashcardReviewService flashcardReviewService,
    required DecksService decksService,
    required INatEnrichmentQueueService enrichmentQueueService,
    required MultipleChoiceDistractorPoolService distractorPoolService,
    DeckSessionPresenter sessionPresenter = const DeckSessionPresenter(),
  }) : _flashcardReviewService = flashcardReviewService,
       _decksService = decksService,
       _enrichmentQueueService = enrichmentQueueService,
       _distractorPoolService = distractorPoolService,
       _sessionPresenter = sessionPresenter;

  Future<DeckSessionData> loadSessionData({
    required BaseDeck deck,
    required DeckConfig config,
  }) async {
    TaxonomyDistractorPools? distractorPools;
    if (config.reviewMode == ReviewMode.multipleChoice) {
      distractorPools = TaxonomyDistractorPools(
        poolService: _distractorPoolService,
        deckSpecies: await _decksService.getSpeciesByDeckId(deck.id!),
        learningMode: config.learningMode,
        nameType: config.nameType,
        language: deck.language,
      );
    }

    final rawCards = await _flashcardReviewService.getFlashCardsForReview(
      deck.id!,
    );
    final imageStagesComplete = _enrichmentQueueService
        .deckInfo(deck.id!)
        .imageStagesComplete;
    final reviewableCards = _sessionPresenter.filterReviewableCards(
      rawCards,
      imageStagesComplete: imageStagesComplete,
    );
    final isWaitingForImages = rawCards.isNotEmpty && reviewableCards.isEmpty;
    final awaitingImageCards = isWaitingForImages
        ? rawCards
        : const <SpeciesWithLocalImages>[];

    final pendingCommonNameSpeciesIds =
        config.learningMode == LearningMode.species &&
            config.nameType == NameType.commonName
        ? await _enrichmentQueueService.pendingCommonNameSpeciesIds(
            reviewableCards.map((card) => card.species.id).toSet(),
          )
        : const <String>{};

    return DeckSessionData(
      reviewableCards: reviewableCards,
      isWaitingForImages: isWaitingForImages,
      awaitingImageCards: awaitingImageCards,
      pendingCommonNameSpeciesIds: pendingCommonNameSpeciesIds,
      distractorPools: distractorPools,
    );
  }

  Future<CardGradeResult> gradeCard({
    required String speciesId,
    required String deckId,
    required ReviewGrade grade,
  }) async {
    final stat = await _flashcardReviewService.reviewCard(
      speciesId,
      deckId,
      grade,
    );
    return CardGradeResult(
      cardState: stat.cardState,
      shouldRequeue: _sessionPresenter.shouldRequeue(stat.cardState),
    );
  }

  Future<List<SpeciesWithLocalImages>> getUnacknowledgedPhotoGaps(
    String deckId,
  ) async {
    final deckSpecies = await _decksService.getSpeciesByDeckId(deckId);
    return _flashcardReviewService.getUnacknowledgedPhotoGaps(
      deckId,
      deckSpecies.map((species) => species.id).toSet(),
    );
  }

  Future<void> removeSpeciesAndAcknowledgeGaps({
    required String deckId,
    required Set<String> toRemove,
    required Set<String> toAcknowledge,
  }) async {
    for (final speciesId in toRemove) {
      await _decksService.removeSpeciesFromDeck(deckId, speciesId);
    }
    if (toAcknowledge.isNotEmpty) {
      await _flashcardReviewService.acknowledgePhotoGaps(
        deckId,
        toAcknowledge,
      );
    }
  }

  Future<void> removeSpeciesFromDeck(String deckId, String speciesId) =>
      _decksService.removeSpeciesFromDeck(deckId, speciesId);

  Future<SpeciesWithLocalImages?> ensureSingleImageForSpecies(
    String speciesId,
  ) => _flashcardReviewService.ensureSingleImageForSpecies(speciesId);

  Future<void> initializeNextBatch(String deckId, {int batchSize = 10}) =>
      _flashcardReviewService.initializeNextBatch(deckId, batchSize: batchSize);

  Future<Map<ReviewGrade, String>> getPreviewIntervals(
    String speciesId,
    String deckId,
  ) => _flashcardReviewService.getPreviewIntervals(speciesId, deckId);
}
