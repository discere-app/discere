import 'package:discere/catalog/model/picture.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/repository/external_id_cache_repository.dart';
import 'package:discere/catalog/repository/external_id_repository.dart';
import 'package:discere/enrichment/mapper/inaturalist_photo_picture_mapper.dart';
import 'package:discere/enrichment/repository/inat_photo_cache_repository.dart';
import 'package:discere/shared/external/inaturalist_service.dart';
import 'package:discere/shared/util/logger.dart';

class SpeciesPhotoService {
  static final _log = Logger.forType(SpeciesPhotoService);
  final INatPhotoCacheRepository _iNatCacheRepository;
  final INaturalistService? _iNatService;
  final ExternalIdRepository? _externalIdRepository;
  final ExternalIdCacheRepository? _externalIdCacheRepository;
  final InaturalistPhotoPictureMapper _mapper;

  SpeciesPhotoService(
    this._iNatCacheRepository, {
    INaturalistService? iNatService,
    ExternalIdRepository? externalIdRepository,
    ExternalIdCacheRepository? externalIdCacheRepository,
    InaturalistPhotoPictureMapper mapper =
        const InaturalistPhotoPictureMapper(),
  }) : _iNatService = iNatService,
       _externalIdRepository = externalIdRepository,
       _externalIdCacheRepository = externalIdCacheRepository,
       _mapper = mapper;

  /// Gibt Referenzbilder + gecachte iNat-Fotos zurück. Kein Netzwerkzugriff.
  Future<List<Picture>> getPhotos(Species species) async {
    final refPictures = List<Picture>.from(species.pictures);

    try {
      final cached = await _iNatCacheRepository.getCachedPhotos(species.id);
      if (cached != null && cached.isNotEmpty) {
        return [...refPictures, ...cached];
      }
    } catch (e) {
      _log.warn('iNat cache read failed for ${species.id}: $e');
    }

    return refPictures;
  }

  /// Wie [getPhotos], fetcht aber live von iNat falls kein Cache-Eintrag
  /// vorhanden ist.
  Future<List<Picture>> getPhotosWithFallback(Species species) async {
    final refPictures = List<Picture>.from(species.pictures);

    try {
      final cached = await _iNatCacheRepository.getCachedPhotos(species.id);
      if (cached != null) {
        return [...refPictures, ...cached];
      }

      if (_iNatService == null) {
        return refPictures;
      }

      final taxonId = await _resolveINatTaxonId(species);
      final result = await _iNatService.fetchPhotos(
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
        'inaturalist',
        result.taxonId.toString(),
      );

      return [...refPictures, ..._mapper.map(species.id, result.photos)];
    } catch (e) {
      _log.warn('iNat live fetch failed for ${species.id}: $e');
      return refPictures;
    }
  }

  Future<int?> _resolveINatTaxonId(Species species) async {
    final referenceId = await _externalIdRepository?.getExternalId(
      species.id,
      'inaturalist',
    );
    final referenceTaxonId = referenceId != null
        ? int.tryParse(referenceId)
        : null;
    if (referenceTaxonId != null) {
      return referenceTaxonId;
    }

    final cachedId = await _externalIdCacheRepository?.getExternalId(
      species.id,
      'inaturalist',
    );
    return cachedId != null ? int.tryParse(cachedId) : null;
  }

  /// Prüft ob ein iNat-Cache-Eintrag für die Species existiert.
  Future<bool> hasCachedPhotos(String speciesId) async {
    try {
      return await _iNatCacheRepository.getCachedPhotos(speciesId) != null;
    } catch (e) {
      _log.warn('iNat cache existence check failed for $speciesId: $e');
      return false;
    }
  }
}
