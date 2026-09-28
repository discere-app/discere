import 'dart:async';
import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/catalog/repository/taxonomy_repository.dart';
import 'package:discere/enrichment/media/service/species_media_service.dart';
import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/external/inaturalist/inat_search_api.dart';
import 'package:discere/learning/decks/service/deck_update_applier.dart';
import 'package:discere/learning/flashcard/repository/species_photo_gap_ack_repository.dart';
import 'package:discere/learning/flashcard/service/deck_session_service.dart';
import 'package:discere/learning/flashcard/service/flashcard_review_service.dart';
import 'package:discere/learning/flashcard/service/fsrs_service.dart';
import 'package:discere/learning/flashcard/service/multiple_choice_distractor_pool_service.dart';
import 'package:discere/learning/import/remote_deck_service.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/learning/repository/deck_config_repository.dart';
import 'package:discere/learning/repository/deck_repository.dart';
import 'package:discere/learning/repository/flashcard_stat_repository.dart';
import 'package:discere/learning/service/deck_import_service.dart';
import 'package:discere/learning/service/deck_lifecycle_observer.dart';
import 'package:discere/learning/service/deck_serialization_worker.dart';
import 'package:discere/learning/service/deck_update_service.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/learning/service/favorite_service.dart';
import 'package:discere/learning/service/flashcard_service.dart';
import 'package:discere/learning/share/deck_export_service.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:discere/shared/service/notification_service.dart';
import 'package:discere/shared/service/user_preferences_service.dart';
import 'package:discere/shared/util/logging_http_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What [buildLearningDeckServices] hands back. Named so
/// [buildLearningReviewServices] can take it as one argument instead of
/// repeating the half of it that it needs.
typedef LearningDeckServices = ({
  FlashcardStatRepository flashcardStatRepository,
  // Exposed only so startDeferred() in the bootstrap can wire up the
  // temporary DeckSourceIdBackfillService. Remove this field too if nothing
  // else needs the raw repository by the time that service is deleted.
  DeckRepository deckRepository,
  DeckConfigRepository deckConfigRepository,
  SpeciesPhotoGapAckRepository speciesPhotoGapAckRepository,
  DecksService deckService,
  DeckImportService deckImportService,
  DeckLifecycleWiring deckLifecycle,
  DeckUpdateApplier deckUpdateApplier,
  RemoteDeckService remoteDeckService,
  DeckUpdateService deckUpdateService,
  DeckExportService deckExportService,
  FavoriteService favoriteService,
  FsrsService fsrsService,
  MultipleChoiceDistractorPoolService multipleChoiceDistractorPoolService,
});

/// Builds the `learning` slice's deck-related services — the subset needed
/// before the `enrichment` slice can be wired up (it depends on
/// [DecksService] via adapters).
///
/// The review services come later, in [buildLearningReviewServices]: they
/// need enrichment's `SpeciesMediaService`, which does not exist yet at this
/// point. Two functions rather than one because the order is real, but both
/// live here, so "where is a learning service built" has one answer.
LearningDeckServices buildLearningDeckServices({
  required SpeciesRepository speciesRepository,
  required TaxonomyRepository taxonomyRepository,
  required ImageService imageService,
  required INatSearchApi iNatSearch,
  required LoggingHttpClient sharedHttpClient,
  required DeckSerializationWorker serializationWorker,
  required SharedPreferences sharedPreferences,
  required UserPreferencesService userPreferencesService,
}) {
  final flashcardStatRepository = FlashcardStatRepository();
  final deckRepository = DeckRepository();
  final deckConfigRepository = DeckConfigRepository();
  final speciesPhotoGapAckRepository = SpeciesPhotoGapAckRepository();

  final deckLifecycle = DeckLifecycleWiring(
    deckConfigRepository: deckConfigRepository,
    userPreferences: userPreferencesService,
  );
  final deckService = DecksService(
    deckRepository,
    flashcardStatRepository,
    speciesRepository,
    imageService,
    deckConfigRepository: deckConfigRepository,
    lifecycleObserver: deckLifecycle,
  );
  final remoteDeckService = RemoteDeckService(
    client: sharedHttpClient,
    serializationWorker: serializationWorker,
  );

  return (
    flashcardStatRepository: flashcardStatRepository,
    deckRepository: deckRepository,
    deckConfigRepository: deckConfigRepository,
    speciesPhotoGapAckRepository: speciesPhotoGapAckRepository,
    deckService: deckService,
    deckLifecycle: deckLifecycle,
    deckImportService: DeckImportService(
      deckService,
      speciesRepository,
      iNatSearch: iNatSearch,
      serializationWorker: serializationWorker,
    ),
    deckUpdateApplier: DeckUpdateApplier(deckService, speciesRepository),
    remoteDeckService: remoteDeckService,
    deckUpdateService: DeckUpdateService(
      deckRepository,
      remoteDeckService,
      sharedPreferences,
    ),
    deckExportService: DeckExportService(
      deckService,
      serializationWorker: serializationWorker,
    ),
    favoriteService: FavoriteService(sharedPreferences),
    fsrsService: FsrsService(),
    multipleChoiceDistractorPoolService: MultipleChoiceDistractorPoolService(
      taxonomyRepository: taxonomyRepository,
    ),
  );
}

/// Fans deck lifecycle events out to the slices that own the follow-up work:
/// a new deck gets its `deck_config` row, a deleted one has its queued
/// enrichment cancelled.
///
/// [cancelDeckEnrichment] is filled in by the composition root once the
/// enrichment queue exists. The two slices depend on each other — enrichment
/// needs the deck service to resolve a deck's species, the deck service
/// needs enrichment to cancel work — so one direction cannot be wired at
/// construction time. That this is the one late binding, and that it sits in
/// the composition root rather than as a mutable field on DecksService, is
/// the point: every other caller gets an observer it cannot forget.
class DeckLifecycleWiring implements DeckLifecycleObserver {
  final DeckConfigRepository _deckConfigRepository;
  final UserPreferencesService _userPreferences;

  /// Set by the composition root after the enrichment queue is built.
  /// Absent until then, which only covers the window before the app runs.
  void Function(String deckId)? cancelDeckEnrichment;

  DeckLifecycleWiring({
    required DeckConfigRepository deckConfigRepository,
    required UserPreferencesService userPreferences,
  }) : _deckConfigRepository = deckConfigRepository,
       _userPreferences = userPreferences;

  @override
  void onDeckCreated(String deckId) {
    unawaited(
      _deckConfigRepository.save(
        DeckConfig(
          deckId: deckId,
          desiredRetention: _userPreferences.defaultDesiredRetention,
        ),
      ),
    );
  }

  @override
  void onDeckDeleted(String deckId) => cancelDeckEnrichment?.call(deckId);
}


/// Builds the `learning` slice's review services, which is everything about
/// answering flashcards.
///
/// Separate from [buildLearningDeckServices] only because of order: these
/// need `SpeciesMediaService` from the `enrichment` slice, and enrichment in
/// turn needs the deck services above. Call this after the enrichment
/// wiring.
({
  FlashcardService flashcardService,
  FlashcardReviewService flashcardReviewService,
  DeckSessionService deckSessionService,
})
buildLearningReviewServices({
  required LearningDeckServices deckServices,
  required SpeciesMediaService speciesMediaService,
  required INatEnrichmentQueueService enrichmentQueueService,
  required NotificationService notificationService,
  required UserPreferencesService userPreferencesService,
}) {
  final flashcardService = FlashcardService(
    deckServices.flashcardStatRepository,
    notificationService,
    deckConfigRepository: deckServices.deckConfigRepository,
    userPreferencesService: userPreferencesService,
  );
  final flashcardReviewService = FlashcardReviewService(
    deckServices.fsrsService,
    deckServices.flashcardStatRepository,
    speciesMediaService,
    deckServices.speciesPhotoGapAckRepository,
    deckConfigRepository: deckServices.deckConfigRepository,
    userPreferencesService: userPreferencesService,
  );
  return (
    flashcardService: flashcardService,
    flashcardReviewService: flashcardReviewService,
    deckSessionService: DeckSessionService(
      flashcardReviewService: flashcardReviewService,
      decksService: deckServices.deckService,
      enrichmentQueueService: enrichmentQueueService,
      distractorPoolService: deckServices.multipleChoiceDistractorPoolService,
    ),
  );
}
