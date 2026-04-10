import 'package:flutter/foundation.dart';
import 'package:discere/shared/service/image_service.dart';

import 'package:discere/enrichment/external/inaturalist_service.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/enrichment/repository/external_id_cache_repository.dart';
import 'package:discere/enrichment/repository/inat_photo_cache_repository.dart';
import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/catalog/service/species_image_service.dart';

class BiologyService {
  final SpeciesRepository _speciesRepository;
  final INatPhotoCacheRepository _iNatCacheRepository;
  final SpeciesImageService _speciesImageService;

  BiologyService(
    this._speciesRepository,
    ImageService imageService,
    this._iNatCacheRepository, {
    INaturalistService? iNatService,
    ExternalIdCacheRepository? externalIdCacheRepository,
    SpeciesImageService? speciesImageService,
  }) : _speciesImageService =
           speciesImageService ??
           SpeciesImageService(
             imageService,
             _iNatCacheRepository,
             iNatService: iNatService,
             externalIdCacheRepository: externalIdCacheRepository,
           );

  Future<Species?> getSpeciesById(String speciesId) {
    return _speciesRepository.getSpeciesById(speciesId);
  }

  Future<bool> hasCachedINatPhotoEntry(String speciesId) async {
    try {
      return await _iNatCacheRepository.getCachedPhotos(speciesId) != null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('iNat cache existence check failed for $speciesId: $e');
      }
      return false;
    }
  }

  Future<SpeciesWithLocalImages?> getSpeciesWithLocalImagesById(
    String speciesId,
  ) async {
    final species = await _speciesRepository.getSpeciesById(speciesId);
    if (species == null) return null;
    return _speciesImageService.getSpeciesWithLocalImages(
      species,
      downloadMissing: true,
    );
  }

  Future<SpeciesWithLocalImages?> getSpeciesWithCachedImagesById(
    String speciesId,
  ) async {
    final species = await _speciesRepository.getSpeciesById(speciesId);
    if (species == null) return null;
    return _speciesImageService.getSpeciesWithLocalImages(
      species,
      downloadMissing: false,
    );
  }

  Future<SpeciesWithLocalImages?> getSpeciesWithCachedOrFetchedImagesById(
    String speciesId,
  ) async {
    final species = await _speciesRepository.getSpeciesById(speciesId);
    if (species == null) return null;
    return _speciesImageService.getSpeciesWithLocalImages(
      species,
      downloadMissing: false,
      fetchLiveINatPhotos: true,
    );
  }
}
