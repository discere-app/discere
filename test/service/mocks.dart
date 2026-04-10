import 'package:discere/enrichment/service/enrichment_service.dart';
import 'package:discere/enrichment/external/inaturalist_service.dart';
import 'package:discere/learning/repository/deck_repository.dart';
import 'package:discere/learning/repository/flash_card_stat_repository.dart';
import 'package:discere/enrichment/repository/inat_photo_cache_repository.dart';
import 'package:discere/enrichment/repository/external_id_cache_repository.dart';
import 'package:discere/enrichment/repository/external_id_repository.dart';
import 'package:discere/enrichment/repository/runtime_common_name_repository.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:discere/catalog/service/species_image_service.dart';
import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/learning/service/import_export_service.dart';
import 'package:discere/shared/service/notification_service.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:mockito/annotations.dart';
import 'package:shared_preferences/shared_preferences.dart';

@GenerateNiceMocks([
  MockSpec<SharedPreferences>(),
  MockSpec<DeckRepository>(),
  MockSpec<SpeciesRepository>(),
  MockSpec<FlashCardStatRepository>(),
  MockSpec<ImageService>(),
  MockSpec<SpeciesImageService>(),
  MockSpec<NotificationService>(),
  MockSpec<DecksService>(),
  MockSpec<EnrichmentService>(),
  MockSpec<ImportExportService>(),
  MockSpec<INaturalistService>(),
  MockSpec<INatPhotoCacheRepository>(),
  MockSpec<ExternalIdRepository>(),
  MockSpec<ExternalIdCacheRepository>(),
  MockSpec<RuntimeCommonNameRepository>(),
])
void main() {}
