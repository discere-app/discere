import 'package:discere/catalog/repository/deprecated_species_name_repository.dart';
import 'package:discere/catalog/repository/external_id_cache_repository.dart';
import 'package:discere/catalog/repository/external_id_rejection_repository.dart';
import 'package:discere/catalog/repository/external_id_repository.dart';
import 'package:discere/catalog/repository/inat_allowed_ancestor_repository.dart';
import 'package:discere/catalog/repository/source_repository.dart';
import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/catalog/repository/taxon_assignment_repository.dart';
import 'package:discere/catalog/repository/taxonomy_repository.dart';
import 'package:discere/enrichment/media/service/species_media_service.dart';
import 'package:discere/enrichment/media/service/species_photo_service.dart';
import 'package:discere/enrichment/pipeline/repository/inat_photo_cache_repository.dart';
import 'package:discere/enrichment/pipeline/repository/runtime_common_name_repository.dart';
import 'package:discere/enrichment/pipeline/service/base_image_enrichment_service.dart';
import 'package:discere/enrichment/pipeline/service/higher_taxon_id_resolver.dart';
import 'package:discere/enrichment/pipeline/service/inat_photo_enrichment_service.dart';
import 'package:discere/enrichment/pipeline/service/inat_taxon_resolver.dart';
import 'package:discere/enrichment/pipeline/service/species_common_name_enrichment_service.dart';
import 'package:discere/enrichment/pipeline/service/taxonomy_common_name_enrichment_service.dart';
import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/external/inaturalist/inat_common_name_api.dart';
import 'package:discere/external/inaturalist/inat_metadata_api.dart';
import 'package:discere/external/inaturalist/inat_photo_api.dart';
import 'package:discere/external/inaturalist/inat_search_api.dart';
import 'package:discere/external/inaturalist/inat_taxon_id_resolver.dart';
import 'package:discere/learning/flashcard/repository/species_photo_gap_ack_repository.dart';
import 'package:discere/learning/flashcard/service/flashcard_review_service.dart';
import 'package:discere/learning/import/remote_deck_service.dart';
import 'package:discere/learning/repository/deck_config_repository.dart';
import 'package:discere/learning/repository/deck_repository.dart';
import 'package:discere/learning/repository/flashcard_stat_mode_repository.dart';
import 'package:discere/learning/repository/flashcard_stat_repository.dart';
import 'package:discere/learning/repository/subdeck_repository.dart';
import 'package:discere/learning/service/answerable_cards_service.dart';
import 'package:discere/learning/service/deck_merge_service.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/learning/service/flashcard_service.dart';
import 'package:discere/learning/share/deck_export_service.dart';
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
  MockSpec<DeprecatedSpeciesNameRepository>(),
  MockSpec<TaxonomyRepository>(),
  MockSpec<FlashcardStatRepository>(),
  MockSpec<FlashcardStatModeRepository>(),
  MockSpec<SubdeckRepository>(),
  MockSpec<AnswerableCardsService>(),
  MockSpec<DeckMergeService>(),
  MockSpec<TaxonAssignmentRepository>(),
  MockSpec<SpeciesPhotoGapAckRepository>(),
  MockSpec<ImageService>(),
  MockSpec<SpeciesMediaService>(),
  MockSpec<SpeciesPhotoService>(),
  MockSpec<NotificationService>(),
  MockSpec<DecksService>(),
  MockSpec<FlashcardService>(),
  MockSpec<FlashcardReviewService>(),
  MockSpec<BaseImageEnrichmentService>(),
  MockSpec<INatPhotoEnrichmentService>(),
  MockSpec<SpeciesCommonNameEnrichmentService>(),
  MockSpec<TaxonomyCommonNameEnrichmentService>(),
  MockSpec<HigherTaxonIdResolver>(),
  MockSpec<DeckExportService>(),
  MockSpec<INatPhotoApi>(),
  MockSpec<INatCommonNameApi>(),
  MockSpec<INatSearchApi>(),
  MockSpec<INatMetadataApi>(),
  MockSpec<INatPhotoCacheRepository>(),
  MockSpec<ExternalIdRepository>(),
  MockSpec<ExternalIdCacheRepository>(),
  MockSpec<ExternalIdRejectionRepository>(),
  MockSpec<INatAllowedAncestorRepository>(),
  MockSpec<INatTaxonResolver>(),
  MockSpec<INatTaxonIdResolver>(),
  MockSpec<RuntimeCommonNameRepository>(),
  MockSpec<SourceRepository>(),
  MockSpec<INatEnrichmentQueueService>(),
])
void main() {}
