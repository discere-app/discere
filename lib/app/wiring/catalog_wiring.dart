import 'package:discere/catalog/model/locale_place_mapping.dart';
import 'package:discere/catalog/repository/external_id_cache_repository.dart';
import 'package:discere/catalog/repository/external_id_repository.dart';
import 'package:discere/catalog/repository/search_repository.dart';
import 'package:discere/catalog/repository/source_repository.dart';
import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/catalog/repository/taxonomy_repository.dart';
import 'package:discere/catalog/service/local_species_image_service.dart';
import 'package:discere/catalog/service/source_service.dart';
import 'package:discere/catalog/service/watchlist_service.dart';
import 'package:discere/external/inaturalist/inaturalist_service.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Builds the `catalog` slice's services. Depends only on `shared`/`external`
/// primitives, per the module dependency matrix in CLAUDE.md.
({
  SpeciesRepository speciesRepository,
  TaxonomyRepository taxonomyRepository,
  SearchRepository searchRepository,
  SourceService sourceService,
  LocalSpeciesImageService localSpeciesImageService,
  ExternalIdRepository externalIdRepository,
  ExternalIdCacheRepository externalIdCacheRepository,
  WatchlistService watchlistService,
})
buildCatalogServices({
  required LocalePlaceMapping? localeMapping,
  required INaturalistService iNatService,
  required ImageService imageService,
  required SharedPreferences sharedPreferences,
}) {
  final speciesRepository = SpeciesRepository(localeMapping: localeMapping);
  final taxonomyRepository = TaxonomyRepository(localeMapping: localeMapping);
  final sourceRepository = SourceRepository();
  final searchRepository = SearchRepository(
    iNatService: iNatService,
    localeMapping: localeMapping,
  );

  return (
    speciesRepository: speciesRepository,
    taxonomyRepository: taxonomyRepository,
    searchRepository: searchRepository,
    sourceService: SourceService(sourceRepository),
    localSpeciesImageService: LocalSpeciesImageService(imageService),
    externalIdRepository: ExternalIdRepository(),
    externalIdCacheRepository: ExternalIdCacheRepository(),
    watchlistService: WatchlistService(sharedPreferences),
  );
}
