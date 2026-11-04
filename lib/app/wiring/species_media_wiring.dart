import 'package:discere/app/species_detail_route.dart';
import 'package:discere/catalog/comparison/comparison_page_opener.dart';
import 'package:discere/catalog/repository/external_id_cache_repository.dart';
import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/catalog/search/species_thumbnail_port.dart';
import 'package:discere/enrichment/media/service/local_species_image_service.dart';
import 'package:discere/enrichment/media/service/species_media_service.dart';
import 'package:discere/enrichment/media/service/species_photo_service.dart';
import 'package:discere/enrichment/media/service/species_thumbnail_service.dart';
import 'package:discere/enrichment/pipeline/repository/inat_photo_cache_repository.dart';
import 'package:discere/enrichment/pipeline/service/inat_taxon_resolver.dart';
import 'package:discere/external/inaturalist/inat_photo_api.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

/// Builds the services that show a species' pictures on demand, outside the
/// background queue: [SpeciesMediaService] for the species page and review
/// sessions, [SpeciesThumbnailService] for a list row's thumbnail. Both read
/// the photos enrichment cached and ask iNaturalist through the same
/// [INatTaxonResolver] it uses.
///
/// Also provides catalog's [ComparisonPageOpener], which shows the
/// comparisons' pictures through [SpeciesMediaService] and opens a species
/// with the app's detail page — neither of which catalog may build itself.
({
  SpeciesMediaService speciesMediaService,
  List<SingleChildWidget> providers,
})
buildSpeciesMediaServices({
  required SpeciesRepository speciesRepository,
  required ImageService imageService,
  required INatPhotoApi iNatPhotos,
  required INatPhotoCacheRepository iNatCacheRepository,
  required INatTaxonResolver taxonResolver,
  required ExternalIdCacheRepository externalIdCacheRepository,
}) {
  final speciesPhotoService = SpeciesPhotoService(
    iNatCacheRepository,
    iNatPhotos: iNatPhotos,
    taxonResolver: taxonResolver,
    externalIdCacheRepository: externalIdCacheRepository,
  );
  final speciesMediaService = SpeciesMediaService(
    speciesRepository,
    speciesPhotoService,
    LocalSpeciesImageService(imageService),
  );
  return (
    speciesMediaService: speciesMediaService,
    providers: [
      Provider<SpeciesMediaService>.value(value: speciesMediaService),
      Provider<SpeciesThumbnailPort>.value(
        value: SpeciesThumbnailService(
          speciesPhotoService: speciesPhotoService,
          taxonResolver: taxonResolver,
          speciesRepository: speciesRepository,
          iNatPhotos: iNatPhotos,
        ),
      ),
      Provider<ComparisonPageOpener>.value(
        value: ComparisonPageOpener(
          resolveFromCache: speciesMediaService.resolveAllFromCache,
          resolveWithDownload: speciesMediaService.resolveAllWithDownload,
          buildSpeciesDetailPage: buildAppSpeciesDetailPage,
        ),
      ),
    ],
  );
}
