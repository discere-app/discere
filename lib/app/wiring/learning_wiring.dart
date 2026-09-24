import 'dart:async';
import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/catalog/repository/taxonomy_repository.dart';
import 'package:discere/external/inaturalist/inat_search_api.dart';
import 'package:discere/learning/decks/service/deck_update_applier.dart';
import 'package:discere/learning/flashcard/repository/species_photo_gap_ack_repository.dart';
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
import 'package:discere/learning/share/import_export_service.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:discere/shared/service/user_preferences_service.dart';
import 'package:discere/shared/util/logging_http_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Builds the `learning` slice's deck-related services — the subset needed
/// before the `enrichment` slice can be wired up (it depends on
/// [DecksService] via adapters). `FlashcardService` itself is built
/// separately in the bootstrap once enrichment's `SpeciesMediaService`
/// exists.
({
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
  ImportExportService importExportService,
  FavoriteService favoriteService,
  FsrsService fsrsService,
  MultipleChoiceDistractorPoolService multipleChoiceDistractorPoolService,
})
buildLearningDeckServices({
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
    importExportService: ImportExportService(
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
