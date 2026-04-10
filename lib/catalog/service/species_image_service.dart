import 'package:flutter/foundation.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:discere/enrichment/external/inaturalist_service.dart';
import 'package:discere/enrichment/external/models/inat_photo.dart';
import 'package:discere/catalog/model/picture.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/enrichment/repository/external_id_cache_repository.dart';
import 'package:discere/enrichment/repository/inat_photo_cache_repository.dart';


class SpeciesImageService {
  final ImageService _imageService;
  final INatPhotoCacheRepository _iNatCacheRepository;
  final INaturalistService? _iNatService;
  final ExternalIdCacheRepository? _externalIdCacheRepository;

  SpeciesImageService(
    this._imageService,
    this._iNatCacheRepository, {
    INaturalistService? iNatService,
    ExternalIdCacheRepository? externalIdCacheRepository,
  }) : _iNatService = iNatService,
       _externalIdCacheRepository = externalIdCacheRepository;

  Future<List<Picture>> withCachedINatPhotos(Species species) async {
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

  Future<List<Picture>> withCachedOrFetchedINatPhotos(Species species) async {
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

  Future<SpeciesWithLocalImages> getSpeciesWithLocalImages(
    Species species, {
    bool downloadMissing = true,
    bool fetchLiveINatPhotos = false,
  }) async {
    final allPictures = fetchLiveINatPhotos
        ? await withCachedOrFetchedINatPhotos(species)
        : await withCachedINatPhotos(species);

    final urlToLocalPath = downloadMissing
        ? await _imageService.downloadAndSavePicturesMap(allPictures)
        : await _imageService.resolveSavedPicturesMap(allPictures);

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
      dangerousToHumans: species.dangerousToHumans,
      fisheriesImportance: species.fisheriesImportance,
      longevityYears: species.longevityYears,
      bodyShape: species.bodyShape,
      trophicLevelFood: species.trophicLevelFood,
      traits: species.traits,
      nativeRegions: species.nativeRegions,
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
