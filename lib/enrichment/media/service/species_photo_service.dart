import 'package:discere/catalog/model/external_id_provider.dart';
import 'package:discere/catalog/model/picture.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/repository/external_id_cache_repository.dart';
import 'package:discere/catalog/repository/external_id_repository.dart';
import 'package:discere/enrichment/pipeline/mapper/inaturalist_photo_picture_mapper.dart';
import 'package:discere/enrichment/pipeline/repository/inat_photo_cache_repository.dart';
import 'package:discere/external/inaturalist/inat_photo_api.dart';
import 'package:discere/shared/util/logger.dart';

class SpeciesPhotoService {
  static final _log = Logger.forType(SpeciesPhotoService);
  final INatPhotoCacheRepository _iNatCacheRepository;
  final INatPhotoApi? _iNatPhotos;
  final ExternalIdRepository? _externalIdRepository;
  final ExternalIdCacheRepository? _externalIdCacheRepository;
  final InaturalistPhotoPictureMapper _mapper;

  SpeciesPhotoService(
    this._iNatCacheRepository, {
    INatPhotoApi? iNatPhotos,
    ExternalIdRepository? externalIdRepository,
    ExternalIdCacheRepository? externalIdCacheRepository,
    InaturalistPhotoPictureMapper mapper =
        const InaturalistPhotoPictureMapper(),
  }) : _iNatPhotos = iNatPhotos,
       _externalIdRepository = externalIdRepository,
       _externalIdCacheRepository = externalIdCacheRepository,
       _mapper = mapper;

  /// Returns reference pictures + cached iNat photos. No network access.
  Future<List<Picture>> getPhotos(Species species) async =>
      (await getPhotosBySpeciesId([species]))[species.id]!;

  /// Like [getPhotos] for several species, with a single cache read: a
  /// session resolves its cards in one batch so the cost does not grow with
  /// the number of due cards.
  Future<Map<String, List<Picture>>> getPhotosBySpeciesId(
    Iterable<Species> species,
  ) async {
    final cached = await getCachedPhotosBySpeciesId(
      species.map((entry) => entry.id).toSet(),
    );

    return {
      for (final entry in species)
        entry.id: [...entry.pictures, ...?cached[entry.id]],
    };
  }

  /// Only the cached iNat photos for [speciesIds], without reference
  /// pictures: for callers that get the reference pictures some other way
  /// than from an already loaded [Species].
  Future<Map<String, List<Picture>>> getCachedPhotosBySpeciesId(
    Set<String> speciesIds,
  ) async {
    try {
      return await _iNatCacheRepository.getCachedPhotosForSpecies(speciesIds);
    } catch (e) {
      // Reference pictures alone make a usable card, so a failed cache read
      // degrades to them rather than losing the load.
      _log.warn('iNat cache read failed for ${speciesIds.length} species: $e');
      return const {};
    }
  }

  /// Like [getPhotos], but fetches live from iNat if there is no cache
  /// entry.
  Future<List<Picture>> getPhotosWithFallback(Species species) async {
    final refPictures = List<Picture>.from(species.pictures);

    try {
      final cached = await _iNatCacheRepository.getCachedPhotos(species.id);
      if (cached != null) {
        return [...refPictures, ...cached];
      }

      if (_iNatPhotos == null) {
        return refPictures;
      }

      final taxonId = await _resolveINatTaxonId(species);
      final result = await _iNatPhotos.fetchPhotos(
        species.getBinomialName(),
        taxonId: taxonId,
        allowTier3Fallback: true,
      );
      if (result == null) {
        return refPictures;
      }

      await _iNatCacheRepository.cachePhotos(species.id, result.photos);
      await _externalIdCacheRepository?.saveExternalId(
        species.id,
        ExternalIdProvider.inaturalist,
        result.taxonId.toString(),
      );
      final wikipediaUrl = result.wikipediaUrl;
      if (wikipediaUrl != null && wikipediaUrl.isNotEmpty) {
        await _externalIdCacheRepository?.saveExternalId(
          species.id,
          ExternalIdProvider.wikipedia,
          wikipediaUrl,
        );
      }
      final iucnStatus = result.iucnStatus;
      if (iucnStatus != null && iucnStatus.isNotEmpty) {
        await _externalIdCacheRepository?.saveExternalId(
          species.id,
          ExternalIdProvider.iucnStatus,
          iucnStatus,
        );
      }

      return [...refPictures, ..._mapper.map(species.id, result.photos)];
    } catch (e) {
      _log.warn('iNat live fetch failed for ${species.id}: $e');
      return refPictures;
    }
  }

  Future<int?> _resolveINatTaxonId(Species species) async {
    final referenceId = await _externalIdRepository?.getExternalId(
      species.id,
      ExternalIdProvider.inaturalist,
    );
    final referenceTaxonId = referenceId != null
        ? int.tryParse(referenceId)
        : null;
    if (referenceTaxonId != null) {
      return referenceTaxonId;
    }

    final cachedId = await _externalIdCacheRepository?.getExternalId(
      species.id,
      ExternalIdProvider.inaturalist,
    );
    return cachedId != null ? int.tryParse(cachedId) : null;
  }

  /// Whether an iNat cache entry exists for the species.
  Future<bool> hasCachedPhotos(String speciesId) async {
    try {
      return await _iNatCacheRepository.getCachedPhotos(speciesId) != null;
    } catch (e) {
      _log.warn('iNat cache existence check failed for $speciesId: $e');
      return false;
    }
  }
}
