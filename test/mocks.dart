import 'package:discere/catalog/repository/external_id_cache_repository.dart';
import 'package:discere/catalog/repository/external_id_repository.dart';
import 'package:discere/catalog/repository/source_repository.dart';
import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/catalog/repository/taxonomy_repository.dart';
import 'package:discere/enrichment/media/service/species_media_service.dart';
import 'package:discere/enrichment/pipeline/repository/inat_photo_cache_repository.dart';
import 'package:discere/enrichment/pipeline/repository/runtime_common_name_repository.dart';
import 'package:discere/enrichment/pipeline/service/base_image_enrichment_service.dart';
import 'package:discere/enrichment/pipeline/service/inat_photo_enrichment_service.dart';
import 'package:discere/enrichment/pipeline/service/species_common_name_enrichment_service.dart';
import 'package:discere/enrichment/pipeline/service/taxonomy_common_name_enrichment_service.dart';
import 'package:discere/external/inaturalist/inat_common_name_api.dart';
import 'package:discere/external/inaturalist/inat_metadata_api.dart';
import 'package:discere/external/inaturalist/inat_photo_api.dart';
import 'package:discere/external/inaturalist/inat_search_api.dart';
import 'package:discere/learning/flashcard/repository/species_photo_gap_ack_repository.dart';
import 'package:discere/learning/flashcard/service/flashcard_review_service.dart';
import 'package:discere/learning/import/remote_deck_service.dart';
import 'package:discere/learning/repository/deck_config_repository.dart';
import 'package:discere/learning/repository/deck_repository.dart';
import 'package:discere/learning/repository/flashcard_stat_repository.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/learning/service/flashcard_service.dart';
import 'package:discere/learning/share/import_export_service.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:discere/shared/service/notification_service.dart';
import 'package:mockito/annotations.dart';
import 'package:shared_preferences/shared_preferences.dart';

@GenerateNiceMocks([
  MockSpec<SharedPreferences>(),
  MockSpec<DeckRepository>(),
  // Added for deck_source_id_backfill_service_test.dart. If that's the only
  // remaining consumer when DeckSourceIdBackfillService is deleted, remove
  // this too.
  MockSpec<RemoteDeckService>(),
  MockSpec<DeckConfigRepository>(),
  MockSpec<SpeciesRepository>(),
  MockSpec<TaxonomyRepository>(),
  MockSpec<FlashcardStatRepository>(),
  MockSpec<SpeciesPhotoGapAckRepository>(),
  MockSpec<ImageService>(),
  MockSpec<SpeciesMediaService>(),
  MockSpec<NotificationService>(),
  MockSpec<DecksService>(),
  MockSpec<FlashcardService>(),
  MockSpec<FlashcardReviewService>(),
  MockSpec<BaseImageEnrichmentService>(),
  MockSpec<INatPhotoEnrichmentService>(),
  MockSpec<SpeciesCommonNameEnrichmentService>(),
  MockSpec<TaxonomyCommonNameEnrichmentService>(),
  MockSpec<ImportExportService>(),
  MockSpec<INatPhotoApi>(),
  MockSpec<INatCommonNameApi>(),
  MockSpec<INatSearchApi>(),
  MockSpec<INatMetadataApi>(),
  MockSpec<INatPhotoCacheRepository>(),
  MockSpec<ExternalIdRepository>(),
  MockSpec<ExternalIdCacheRepository>(),
  MockSpec<RuntimeCommonNameRepository>(),
  MockSpec<SourceRepository>(),
])
void main() {}
