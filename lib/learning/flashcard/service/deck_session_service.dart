import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/learning/flashcard/answer_options_presenter.dart';
import 'package:discere/learning/flashcard/deck_session_presenter.dart';
import 'package:discere/learning/flashcard/service/flashcard_review_service.dart';
import 'package:discere/learning/flashcard/service/fsrs_service.dart';
import 'package:discere/learning/flashcard/service/multiple_choice_distractor_pool_service.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/learning/model/flashcard_stat.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/shared/model/language.dart';

/// Everything [DeckSessionService.loadSessionData] fetches to (re)start a
/// review session for a given [DeckConfig] — bundles several independent
/// async lookups (deck species, distractor pools, due cards, image-wait
/// state, pending-common-name state) that [DeckPageState] previously
/// performed directly, one after another, into a single call.
class DeckSessionData {
  final List<SpeciesWithLocalImages> reviewableCards;
  final bool isWaitingForImages;
  final List<SpeciesWithLocalImages> awaitingImageCards;
  final List<String> deckNamePool;
  final Map<String, List<String>> taxonomyPoolByScopeId;
  final Set<String> pendingCommonNameSpeciesIds;

  const DeckSessionData({
    required this.reviewableCards,
    required this.isWaitingForImages,
    required this.awaitingImageCards,
    required this.deckNamePool,
    required this.taxonomyPoolByScopeId,
    required this.pendingCommonNameSpeciesIds,
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
  final AnswerOptionsPresenter _answerOptionsPresenter;

  const DeckSessionService({
    required FlashcardReviewService flashcardReviewService,
    required DecksService decksService,
    required INatEnrichmentQueueService enrichmentQueueService,
    required MultipleChoiceDistractorPoolService distractorPoolService,
    DeckSessionPresenter sessionPresenter = const DeckSessionPresenter(),
    AnswerOptionsPresenter answerOptionsPresenter = const AnswerOptionsPresenter(),
  }) : _flashcardReviewService = flashcardReviewService,
       _decksService = decksService,
       _enrichmentQueueService = enrichmentQueueService,
       _distractorPoolService = distractorPoolService,
       _sessionPresenter = sessionPresenter,
       _answerOptionsPresenter = answerOptionsPresenter;

  /// The ancestor id a card's taxonomy-scoped distractor pool is grouped by
  /// for [learningMode]: same genus for species mode, same family for genus
  /// mode, same order for family mode. `null` when [species] is missing that
  /// classification id (e.g. an imported species without full reference-DB
  /// linkage) — callers fall back to the whole-deck pool in that case.
  String? scopeIdFor(LearningMode learningMode, Species species) =>
      switch (learningMode) {
        LearningMode.species => species.classification.genusId,
        LearningMode.genus => species.classification.familyId,
        LearningMode.family => species.classification.orderId,
      };

  Future<DeckSessionData> loadSessionData({
    required BaseDeck deck,
    required DeckConfig config,
  }) async {
    var deckNamePool = <String>[];
    var taxonomyPoolByScopeId = <String, List<String>>{};
    if (config.reviewMode == ReviewMode.multipleChoice) {
      final deckSpecies = await _decksService.getSpeciesByDeckId(deck.id!);
      deckNamePool = _answerOptionsPresenter.distinctPrimaryNames(
        deckSpecies,
        deck.language,
        config.learningMode,
        config.nameType,
      );
      taxonomyPoolByScopeId = await _buildTaxonomyPoolsByScopeId(
        deckSpecies,
        config,
        deck.language,
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
      deckNamePool: deckNamePool,
      taxonomyPoolByScopeId: taxonomyPoolByScopeId,
      pendingCommonNameSpeciesIds: pendingCommonNameSpeciesIds,
    );
  }

  /// Builds one distractor pool per distinct scope (see [scopeIdFor])
  /// actually present among [deckSpecies], so every card sharing that scope
  /// can reuse the same precomputed pool.
  Future<Map<String, List<String>>> _buildTaxonomyPoolsByScopeId(
    List<Species> deckSpecies,
    DeckConfig config,
    Language language,
  ) async {
    final representativeByScopeId = <String, Species>{};
    for (final species in deckSpecies) {
      final scopeId = scopeIdFor(config.learningMode, species);
      if (scopeId == null) continue;
      representativeByScopeId.putIfAbsent(scopeId, () => species);
    }

    final pools = <String, List<String>>{};
    for (final entry in representativeByScopeId.entries) {
      pools[entry.key] = await _distractorPoolService.buildPool(
        currentSpecies: entry.value,
        deckSpecies: deckSpecies,
        learningMode: config.learningMode,
        language: language,
        nameType: config.nameType,
      );
    }
    return pools;
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
