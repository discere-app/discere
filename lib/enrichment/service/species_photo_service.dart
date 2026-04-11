import 'package:flutter/foundation.dart';
import 'package:discere/catalog/model/picture.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/shared/external/inaturalist_service.dart';
import 'package:discere/enrichment/mapper/inaturalist_photo_picture_mapper.dart';
import 'package:discere/catalog/repository/external_id_cache_repository.dart';
import 'package:discere/enrichment/repository/inat_photo_cache_repository.dart';

class SpeciesPhotoService {
  final INatPhotoCacheRepository _iNatCacheRepository;
  final INaturalistService? _iNatService;
  final ExternalIdCacheRepository? _externalIdCacheRepository;
  final InaturalistPhotoPictureMapper _mapper;

  SpeciesPhotoService(
    this._iNatCacheRepository, {
    INaturalistService? iNatService,
    ExternalIdCacheRepository? externalIdCacheRepository,
    InaturalistPhotoPictureMapper mapper =
        const InaturalistPhotoPictureMapper(),
  }) : _iNatService = iNatService,
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
      if (kDebugMode) {
        debugPrint('iNat cache read failed for ${species.id}: $e');
      }
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

      final result = await _iNatService.fetchPhotos(species.getBinomialName());
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
      if (kDebugMode) {
        debugPrint('iNat live fetch failed for ${species.id}: $e');
      }
      return refPictures;
    }
  }

  /// Prüft ob ein iNat-Cache-Eintrag für die Species existiert.
  Future<bool> hasCachedPhotos(String speciesId) async {
    try {
      return await _iNatCacheRepository.getCachedPhotos(speciesId) != null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('iNat cache existence check failed for $speciesId: $e');
      }
      return false;
    }
  }
}
