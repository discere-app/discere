import 'package:discere/catalog/repository/external_id_cache_repository.dart';
import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/enrichment/media/service/local_species_image_service.dart';
import 'package:discere/enrichment/media/service/species_media_service.dart';
import 'package:discere/enrichment/media/service/species_photo_service.dart';
import 'package:discere/enrichment/media/service/species_thumbnail_service.dart';
import 'package:discere/enrichment/pipeline/repository/inat_photo_cache_repository.dart';
import 'package:discere/enrichment/pipeline/service/inat_taxon_resolver.dart';
import 'package:discere/external/inaturalist/inat_photo_api.dart';
import 'package:discere/shared/service/image_service.dart';

/// Builds the services that show a species' pictures on demand, outside the
/// background queue: [SpeciesMediaService] for the species page and review
/// sessions, [SpeciesThumbnailService] for a list row's thumbnail. Both read
/// the photos enrichment cached and ask iNaturalist through the same
/// [INatTaxonResolver] it uses.
({
  SpeciesMediaService speciesMediaService,
  SpeciesThumbnailService speciesThumbnailService,
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
  return (
    speciesMediaService: SpeciesMediaService(
      speciesRepository,
      speciesPhotoService,
      LocalSpeciesImageService(imageService),
    ),
    speciesThumbnailService: SpeciesThumbnailService(
      speciesPhotoService: speciesPhotoService,
      taxonResolver: taxonResolver,
      speciesRepository: speciesRepository,
      iNatPhotos: iNatPhotos,
    ),
  );
}
