import 'package:discere/enrichment/service/enrichment_service.dart';
import 'package:discere/shared/external/inaturalist_service.dart';
import 'package:discere/learning/repository/deck_repository.dart';
import 'package:discere/learning/repository/flashcard_stat_repository.dart';
import 'package:discere/enrichment/repository/inat_photo_cache_repository.dart';
import 'package:discere/catalog/repository/external_id_cache_repository.dart';
import 'package:discere/catalog/repository/external_id_repository.dart';
import 'package:discere/enrichment/repository/runtime_common_name_repository.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:discere/application/species_media/species_media_service.dart';
import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/learning/service/import_export_service.dart';
import 'package:discere/shared/service/notification_service.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/learning/service/flashcard_service.dart';
import 'package:mockito/annotations.dart';
import 'package:shared_preferences/shared_preferences.dart';

@GenerateNiceMocks([
  MockSpec<SharedPreferences>(),
  MockSpec<DeckRepository>(),
  MockSpec<SpeciesRepository>(),
  MockSpec<FlashcardStatRepository>(),
  MockSpec<ImageService>(),
  MockSpec<SpeciesMediaService>(),
  MockSpec<NotificationService>(),
  MockSpec<DecksService>(),
  MockSpec<FlashcardService>(),
  MockSpec<EnrichmentService>(),
  MockSpec<ImportExportService>(),
  MockSpec<INaturalistService>(),
  MockSpec<INatPhotoCacheRepository>(),
  MockSpec<ExternalIdRepository>(),
  MockSpec<ExternalIdCacheRepository>(),
  MockSpec<RuntimeCommonNameRepository>(),
])
void main() {}
