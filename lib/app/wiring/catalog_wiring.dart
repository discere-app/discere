import 'package:discere/catalog/model/locale_place_mapping.dart';
import 'package:discere/catalog/repository/external_id_cache_repository.dart';
import 'package:discere/catalog/repository/external_id_repository.dart';
import 'package:discere/catalog/repository/locale_place_mapping_repository.dart';
import 'package:discere/catalog/repository/search_repository.dart';
import 'package:discere/catalog/repository/source_repository.dart';
import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/catalog/repository/taxonomy_repository.dart';
import 'package:discere/catalog/search/search_worker.dart';
import 'package:discere/catalog/service/source_service.dart';
import 'package:discere/catalog/service/species_search_service.dart';
import 'package:discere/catalog/service/watchlist_service.dart';
import 'package:discere/catalog/species_detail/service/species_inat_metadata_service.dart';
import 'package:discere/catalog/taxonomy_detail/service/taxonomy_service.dart';
import 'package:discere/external/inaturalist/inat_metadata_api.dart';
import 'package:discere/external/inaturalist/inat_search_api.dart';
import 'package:discere/external/wikipedia/wikipedia_service.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Builds the `catalog` slice's services. Depends only on `shared`/`external`
/// primitives, per the module dependency matrix in CLAUDE.md.
({
  SpeciesRepository speciesRepository,
  TaxonomyRepository taxonomyRepository,
  SearchRepository searchRepository,
  SourceService sourceService,
  ExternalIdRepository externalIdRepository,
  ExternalIdCacheRepository externalIdCacheRepository,
  WatchlistService watchlistService,
  WikipediaService wikipediaService,
  SpeciesInatMetadataService speciesInatMetadataService,
  SpeciesSearchService speciesSearchService,
  TaxonomyService taxonomyService,
  List<SingleChildWidget> providers,
})
buildCatalogServices({
  required LocalePlaceMapping? localeMapping,
  required LocalePlaceMappingRepository localePlaceMappingRepository,
  required INatSearchApi iNatSearch,
  required INatMetadataApi iNatMetadata,
  required WikipediaService wikipediaService,
  required SharedPreferences sharedPreferences,
}) {
  final speciesRepository = SpeciesRepository(localeMapping: localeMapping);
  final taxonomyRepository = TaxonomyRepository(localeMapping: localeMapping);
  final sourceRepository = SourceRepository();
  final searchRepository = SearchRepository(
    iNatSearch: iNatSearch,
    localeMapping: localeMapping,
    searchWorker: SearchWorker(),
  );
  final externalIdRepository = ExternalIdRepository();
  final externalIdCacheRepository = ExternalIdCacheRepository();

  final sourceService = SourceService(sourceRepository);
  final watchlistService = WatchlistService(sharedPreferences);
  final speciesSearchService = SpeciesSearchService(searchRepository);
  final taxonomyService = TaxonomyService(taxonomyRepository);
  final speciesInatMetadataService = SpeciesInatMetadataService(
    iNatMetadata,
    externalIdRepository: externalIdRepository,
    externalIdCacheRepository: externalIdCacheRepository,
  );

  return (
    speciesRepository: speciesRepository,
    taxonomyRepository: taxonomyRepository,
    searchRepository: searchRepository,
    sourceService: sourceService,
    externalIdRepository: externalIdRepository,
    externalIdCacheRepository: externalIdCacheRepository,
    watchlistService: watchlistService,
    wikipediaService: wikipediaService,
    speciesSearchService: speciesSearchService,
    taxonomyService: taxonomyService,
    speciesInatMetadataService: speciesInatMetadataService,
    providers: [
      Provider<SpeciesSearchService>.value(value: speciesSearchService),
      Provider<TaxonomyService>.value(value: taxonomyService),
      Provider<LocalePlaceMappingRepository>.value(
        value: localePlaceMappingRepository,
      ),
      ChangeNotifierProvider<WatchlistService>.value(value: watchlistService),
      Provider<SourceService>.value(value: sourceService),
      Provider<SpeciesInatMetadataService>.value(
        value: speciesInatMetadataService,
      ),
    ],
  );
}
