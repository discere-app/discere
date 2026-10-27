import 'package:discere/app/wiring/deck_lifecycle_wiring.dart';
import 'package:discere/catalog/repository/deprecated_species_name_repository.dart';
import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/catalog/repository/taxon_assignment_repository.dart';
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
import 'package:discere/learning/import/import_text_recognizer.dart';
import 'package:discere/learning/import/remote_deck_service.dart';
import 'package:discere/learning/repository/deck_config_repository.dart';
import 'package:discere/learning/repository/deck_merge_repository.dart';
import 'package:discere/learning/repository/deck_repository.dart';
import 'package:discere/learning/repository/flashcard_stat_mode_repository.dart';
import 'package:discere/learning/repository/flashcard_stat_repository.dart';
import 'package:discere/learning/repository/subdeck_repository.dart';
import 'package:discere/learning/service/answerable_cards_service.dart';
import 'package:discere/learning/service/deck_import_service.dart';
import 'package:discere/learning/service/deck_merge_service.dart';
import 'package:discere/learning/service/deck_serialization_worker.dart';
import 'package:discere/learning/service/deck_update_service.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/learning/service/favorite_service.dart';
import 'package:discere/learning/service/flashcard_service.dart';
import 'package:discere/learning/share/deck_export_service.dart';
import 'package:discere/shared/persistence/user_data_writes.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:discere/shared/service/notification_service.dart';
import 'package:discere/shared/service/user_preferences_service.dart';
import 'package:discere/shared/util/logging_http_client.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What [buildLearningDeckServices] hands back. Named so
/// [buildLearningReviewServices] can take it as one argument instead of
/// repeating the half of it that it needs.
typedef LearningDeckServices = ({
  FlashcardStatRepository flashcardStatRepository,
  FlashcardStatModeRepository flashcardStatModeRepository,
  AnswerableCardsService answerableCardsService,
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
  UserDataWrites userDataWrites,
  List<SingleChildWidget> providers,
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
  required UserDataWrites userDataWrites,
}) {
  final flashcardStatRepository = FlashcardStatRepository();
  final flashcardStatModeRepository = FlashcardStatModeRepository();
  final subdeckRepository = SubdeckRepository();
  final answerableCardsService = AnswerableCardsService(
    flashcardStatRepository,
    flashcardStatModeRepository,
    TaxonAssignmentRepository(),
    subdeckRepository,
  );
  final deckRepository = DeckRepository();
  final deckConfigRepository = DeckConfigRepository();
  final speciesPhotoGapAckRepository = SpeciesPhotoGapAckRepository();

  final deckLifecycle = DeckLifecycleWiring(
    deckConfigRepository: deckConfigRepository,
    userPreferences: userPreferencesService,
    userDataWrites: userDataWrites,
  );
  final deckService = DecksService(
    deckRepository,
    flashcardStatRepository,
    speciesRepository,
    imageService,
    subdeckRepository: subdeckRepository,
    deckConfigRepository: deckConfigRepository,
    lifecycleObserver: deckLifecycle,
    answerableCards: answerableCardsService,
    userDataWrites: userDataWrites,
  );
  final remoteDeckService = RemoteDeckService(
    client: sharedHttpClient,
    serializationWorker: serializationWorker,
  );
  final deckImportService = DeckImportService(
    deckService,
    speciesRepository,
    userDataWrites: userDataWrites,
    iNatSearch: iNatSearch,
  );
  final importTextRecognizer = ImportTextRecognizer(serializationWorker);
  final deckUpdateApplier = DeckUpdateApplier(
    deckService,
    speciesRepository,
    deprecatedNames: DeprecatedSpeciesNameRepository(),
    userDataWrites: userDataWrites,
  );
  final deckUpdateService = DeckUpdateService(
    deckRepository,
    remoteDeckService,
    sharedPreferences,
  );
  final deckExportService = DeckExportService(
    deckService,
    fileSaver: FilePicker.saveFile,
    serializationWorker: serializationWorker,
  );
  final favoriteService = FavoriteService(sharedPreferences);
  final deckMergeService = DeckMergeService(
    deckService,
    deckImportService,
    mergeRepository: DeckMergeRepository(),
    subdeckRepository: subdeckRepository,
    deckConfigRepository: deckConfigRepository,
    favoriteService: favoriteService,
    userDataWrites: userDataWrites,
  );

  return (
    flashcardStatRepository: flashcardStatRepository,
    flashcardStatModeRepository: flashcardStatModeRepository,
    answerableCardsService: answerableCardsService,
    deckRepository: deckRepository,
    deckConfigRepository: deckConfigRepository,
    speciesPhotoGapAckRepository: speciesPhotoGapAckRepository,
    deckService: deckService,
    deckLifecycle: deckLifecycle,
    deckImportService: deckImportService,
    deckUpdateApplier: deckUpdateApplier,
    remoteDeckService: remoteDeckService,
    deckUpdateService: deckUpdateService,
    deckExportService: deckExportService,
    favoriteService: favoriteService,
    fsrsService: FsrsService(),
    multipleChoiceDistractorPoolService: MultipleChoiceDistractorPoolService(
      taxonomyRepository: taxonomyRepository,
    ),
    userDataWrites: userDataWrites,
    providers: [
      ChangeNotifierProvider<DecksService>.value(value: deckService),
      Provider<DeckExportService>.value(value: deckExportService),
      Provider<DeckImportService>.value(value: deckImportService),
      Provider<ImportTextRecognizer>.value(value: importTextRecognizer),
      Provider<DeckUpdateApplier>.value(value: deckUpdateApplier),
      Provider<RemoteDeckService>.value(value: remoteDeckService),
      ChangeNotifierProvider<DeckUpdateService>.value(value: deckUpdateService),
      ChangeNotifierProvider<FavoriteService>.value(value: favoriteService),
      Provider<DeckMergeService>.value(value: deckMergeService),
    ],
  );
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
  List<SingleChildWidget> providers,
})
buildLearningReviewServices({
  required LearningDeckServices deckServices,
  required SpeciesMediaService speciesMediaService,
  required INatEnrichmentQueueService enrichmentQueueService,
  required NotificationService notificationService,
  required UserPreferencesService userPreferencesService,
}) {
  final flashcardService = FlashcardService(
    notificationService,
    answerableCards: deckServices.answerableCardsService,
    deckConfigRepository: deckServices.deckConfigRepository,
    userPreferencesService: userPreferencesService,
  );
  final flashcardReviewService = FlashcardReviewService(
    deckServices.flashcardStatRepository,
    speciesMediaService,
    deckServices.speciesPhotoGapAckRepository,
    modeStats: deckServices.flashcardStatModeRepository,
    answerableCards: deckServices.answerableCardsService,
    userDataWrites: deckServices.userDataWrites,
  );
  final deckSessionService = DeckSessionService(
    flashcardReviewService: flashcardReviewService,
    decksService: deckServices.deckService,
    answerableCards: deckServices.answerableCardsService,
    enrichmentQueueService: enrichmentQueueService,
    distractorPoolService: deckServices.multipleChoiceDistractorPoolService,
    userDataWrites: deckServices.userDataWrites,
  );
  return (
    flashcardService: flashcardService,
    flashcardReviewService: flashcardReviewService,
    deckSessionService: deckSessionService,
    providers: [
      Provider<FlashcardService>.value(value: flashcardService),
      Provider<DeckSessionService>.value(value: deckSessionService),
    ],
  );
}
