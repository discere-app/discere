import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/external/inaturalist/inaturalist_service.dart';
import 'package:discere/learning/repository/deck_config_repository.dart';
import 'package:discere/learning/repository/deck_repository.dart';
import 'package:discere/learning/repository/flashcard_stat_repository.dart';
import 'package:discere/learning/repository/species_photo_gap_ack_repository.dart';
import 'package:discere/learning/service/deck_import_service.dart';
import 'package:discere/learning/service/deck_serialization_worker.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/learning/service/favorite_service.dart';
import 'package:discere/learning/service/fsrs_service.dart';
import 'package:discere/learning/service/import_export_service.dart';
import 'package:discere/learning/service/remote_deck_service.dart';
import 'package:discere/shared/service/image_service.dart';
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
  RemoteDeckService remoteDeckService,
  ImportExportService importExportService,
  FavoriteService favoriteService,
  FsrsService fsrsService,
})
buildLearningDeckServices({
  required SpeciesRepository speciesRepository,
  required ImageService imageService,
  required INaturalistService iNatService,
  required LoggingHttpClient sharedHttpClient,
  required DeckSerializationWorker serializationWorker,
  required SharedPreferences sharedPreferences,
}) {
  final flashcardStatRepository = FlashcardStatRepository();
  final deckRepository = DeckRepository();
  final deckConfigRepository = DeckConfigRepository();
  final speciesPhotoGapAckRepository = SpeciesPhotoGapAckRepository();

  final deckService = DecksService(
    deckRepository,
    flashcardStatRepository,
    speciesRepository,
    imageService,
    deckConfigRepository: deckConfigRepository,
  );

  return (
    flashcardStatRepository: flashcardStatRepository,
    deckRepository: deckRepository,
    deckConfigRepository: deckConfigRepository,
    speciesPhotoGapAckRepository: speciesPhotoGapAckRepository,
    deckService: deckService,
    deckImportService: DeckImportService(
      deckService,
      speciesRepository,
      iNatService: iNatService,
      serializationWorker: serializationWorker,
    ),
    remoteDeckService: RemoteDeckService(
      client: sharedHttpClient,
      serializationWorker: serializationWorker,
    ),
    importExportService: ImportExportService(
      deckService,
      serializationWorker: serializationWorker,
    ),
    favoriteService: FavoriteService(sharedPreferences),
    fsrsService: FsrsService(),
  );
}
