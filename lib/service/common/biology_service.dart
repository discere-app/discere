import 'package:flutter/foundation.dart';

import 'image_service.dart';
import '../../model/biology/picture.dart';
import '../../model/biology/species.dart';
import '../../model/biology/species_with_local_images.dart';
import '../../persistence/inat_photo_cache_repository.dart';
import '../../persistence/species_repository.dart';

class BiologyService {
  final SpeciesRepository _speciesRepository;
  final ImageService _imageService;
  final INatPhotoCacheRepository _iNatCacheRepository;

  BiologyService(
    this._speciesRepository,
    this._imageService,
    this._iNatCacheRepository,
  );

  Future<Species?> getSpeciesById(String speciesId) {
    return _speciesRepository.getSpeciesById(speciesId);
  }

  Future<SpeciesWithLocalImages?> getSpeciesWithLocalImagesById(
      String speciesId) async {
    final species = await _speciesRepository.getSpeciesById(speciesId);
    if (species == null) return null;

    // Combine reference DB pictures with any already-cached iNat photos.
    final allPictures = await _withCachedINatPhotos(species);

    final urlsToDownload = allPictures
        .map((p) => p.url)
        .where((url) => url != null && url.isNotEmpty)
        .cast<String>()
        .toSet();

    final urlToLocalPath =
        await _imageService.downloadAndSaveImagesMap(urlsToDownload);

    final localPictures = allPictures.map((p) {
      if (p.url != null && urlToLocalPath.containsKey(p.url)) {
        return LocalPicture(p, urlToLocalPath[p.url]!);
      }
      return null;
    }).whereType<LocalPicture>().toList();

    return SpeciesWithLocalImages(species, localPictures);
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
}
