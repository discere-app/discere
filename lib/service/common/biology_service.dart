import 'package:flutter/foundation.dart';

import '../../external/inaturalist/inaturalist_service.dart';
import '../../external/inaturalist/models/inat_photo.dart';
import 'image_service.dart';
import '../../model/biology/picture.dart';
import '../../model/biology/species.dart';
import '../../model/biology/species_with_local_images.dart';
import '../../persistence/external_id_cache_repository.dart';
import '../../persistence/inat_photo_cache_repository.dart';
import '../../persistence/species_repository.dart';

class BiologyService {
  final SpeciesRepository _speciesRepository;
  final ImageService _imageService;
  final INatPhotoCacheRepository _iNatCacheRepository;
  final INaturalistService? _iNatService;
  final ExternalIdCacheRepository? _externalIdCacheRepository;

  BiologyService(
    this._speciesRepository,
    this._imageService,
    this._iNatCacheRepository, {
    INaturalistService? iNatService,
    ExternalIdCacheRepository? externalIdCacheRepository,
  }) : _iNatService = iNatService,
       _externalIdCacheRepository = externalIdCacheRepository;

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

    // Combine reference DB pictures with any already-cached iNat photos.
    final allPictures = await _withCachedINatPhotos(species);
    final urlToLocalPath = await _imageService.downloadAndSavePicturesMap(
      allPictures,
    );

    final localPictures = allPictures
        .map((p) {
          if (p.url != null && urlToLocalPath.containsKey(p.url)) {
            return LocalPicture(p, urlToLocalPath[p.url]!);
          }
          return null;
        })
        .whereType<LocalPicture>()
        .toList();

    return SpeciesWithLocalImages(
      _copySpeciesWithPictures(species, allPictures),
      localPictures,
    );
  }

  Future<SpeciesWithLocalImages?> getSpeciesWithCachedImagesById(
    String speciesId,
  ) async {
    final species = await _speciesRepository.getSpeciesById(speciesId);
    if (species == null) return null;

    final allPictures = await _withCachedINatPhotos(species);
    final urlToLocalPath = await _imageService.resolveSavedPicturesMap(
      allPictures,
    );

    final localPictures = allPictures
        .map((picture) {
          if (picture.url != null && urlToLocalPath.containsKey(picture.url)) {
            return LocalPicture(picture, urlToLocalPath[picture.url]!);
          }
          return null;
        })
        .whereType<LocalPicture>()
        .toList();

    return SpeciesWithLocalImages(
      _copySpeciesWithPictures(species, allPictures),
      localPictures,
    );
  }

  Future<SpeciesWithLocalImages?> getSpeciesWithCachedOrFetchedImagesById(
    String speciesId,
  ) async {
    final species = await _speciesRepository.getSpeciesById(speciesId);
    if (species == null) return null;

    final allPictures = await _withCachedOrFetchedINatPhotos(species);
    final urlToLocalPath = await _imageService.resolveSavedPicturesMap(
      allPictures,
    );

    final localPictures = allPictures
        .map((picture) {
          if (picture.url != null && urlToLocalPath.containsKey(picture.url)) {
            return LocalPicture(picture, urlToLocalPath[picture.url]!);
          }
          return null;
        })
        .whereType<LocalPicture>()
        .toList();

    return SpeciesWithLocalImages(
      _copySpeciesWithPictures(species, allPictures),
      localPictures,
    );
  }

  /// Appends any already-cached iNat photos to the species' reference pictures.
  ///
  /// Does NOT trigger an API call — only reads from the local cache.
  /// iNat photos are fetched at deck creation/import time, not at view time.
  Future<List<Picture>> _withCachedINatPhotos(Species species) async {
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

  Future<List<Picture>> _withCachedOrFetchedINatPhotos(Species species) async {
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
      return [
        ...refPictures,
        ..._mapINatPhotosToPictures(species.id, result.photos),
      ];
    } catch (e) {
      if (kDebugMode) {
        debugPrint('iNat live fetch failed for ${species.id}: $e');
      }
      return refPictures;
    }
  }

  Species _copySpeciesWithPictures(Species species, List<Picture> pictures) {
    return Species(
      species.id,
      species.externalId,
      species.externalSource,
      species.scientificName,
      species.commonNames,
      species.classification,
      pictures,
      size: species.size,
      depth: species.depth,
      habitat: species.habitat,
      conservation: species.conservation,
      status: species.status,
    );
  }

  List<Picture> _mapINatPhotosToPictures(
    String speciesId,
    List<INatPhoto> photos,
  ) {
    return photos
        .map(
          (photo) => Picture(
            id: 'inat_${speciesId}_${photo.mediumUrl.hashCode}',
            species: speciesId,
            url: photo.mediumUrl,
            author: photo.attribution,
            origin: 'iNaturalist',
            licenseKey: (photo.licenseCode ?? '').toUpperCase(),
            isUsable: 1,
          ),
        )
        .toList();
  }
}
