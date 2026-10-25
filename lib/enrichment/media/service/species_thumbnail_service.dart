import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/catalog/search/species_thumbnail_port.dart';
import 'package:discere/enrichment/media/service/species_photo_service.dart';
import 'package:discere/enrichment/pipeline/service/inat_taxon_resolver.dart';
import 'package:discere/external/inaturalist/inat_photo_api.dart';
import 'package:discere/external/inaturalist/inat_taxon_id_resolver.dart';
import 'package:discere/shared/util/logger.dart';

/// The thumbnail a species list shows for one of its rows: an iNaturalist
/// photo of the taxon the species maps to, checked the same way the species
/// page and enrichment check it.
///
/// Each step is cheaper than the next, so the first that answers wins:
/// photos enrichment already cached cost no request, a taxon id on record
/// costs one, and only a species with neither is loaded and searched for.
/// Nothing is downloaded or cached here beyond an id the search found.
class SpeciesThumbnailService implements SpeciesThumbnailPort {
  static final _log = Logger.forType(SpeciesThumbnailService);

  final SpeciesPhotoService _speciesPhotoService;
  final INatTaxonResolver _taxonResolver;
  final SpeciesRepository _speciesRepository;
  final INatPhotoApi _iNatPhotos;

  const SpeciesThumbnailService({
    required SpeciesPhotoService speciesPhotoService,
    required INatTaxonResolver taxonResolver,
    required SpeciesRepository speciesRepository,
    required INatPhotoApi iNatPhotos,
  }) : _speciesPhotoService = speciesPhotoService,
       _taxonResolver = taxonResolver,
       _speciesRepository = speciesRepository,
       _iNatPhotos = iNatPhotos;

  @override
  Future<String?> thumbnailUrl(String speciesId) async {
    try {
      final cachedBySpeciesId = await _speciesPhotoService
          .getCachedPhotosBySpeciesId({speciesId});
      final cached = cachedBySpeciesId[speciesId];
      // An empty entry records that iNaturalist has no photos for it.
      if (cached != null) return cached.firstOrNull?.url;

      final knownTaxonId = await _taxonResolver.knownTaxonId(speciesId);
      if (knownTaxonId != null) {
        return await _iNatPhotos.fetchThumbnailUrl(knownTaxonId);
      }
      return await _searchedThumbnailUrl(speciesId);
    } on TaxonNotFoundException {
      return null;
    } catch (e) {
      _log.warn('Thumbnail lookup failed for $speciesId: $e');
      return null;
    }
  }

  /// Searches the taxon by name, with the ETL's rejections and the phylum
  /// check that keep a homonym's photo away from the species. Keeps a found
  /// id, so the next lookup of this species — here or anywhere else — need
  /// not search again.
  Future<String?> _searchedThumbnailUrl(String speciesId) async {
    final species = await _speciesRepository.getSpeciesById(speciesId);
    if (species == null) return null;
    final taxonId = await _taxonResolver.searchTaxonId(species);
    if (taxonId == null) return null;
    await _taxonResolver.persistResolvedTaxonId(
      species,
      previousTaxonId: null,
      resolvedTaxonId: taxonId,
    );
    return _iNatPhotos.fetchThumbnailUrl(taxonId);
  }
}
