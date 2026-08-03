import 'package:discere/catalog/model/picture.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/shared/service/image_service.dart';

class LocalSpeciesImageService {
  static const _referenceImagesDirectory = 'reference_images';
  static const _externalImagesDirectory = 'external_images';

  final ImageService _imageService;

  const LocalSpeciesImageService(this._imageService);

  /// Löst [pictures] auf lokale Dateipfade auf und gibt [SpeciesWithLocalImages]
  /// zurück. Unterscheidet nicht, woher die Pictures stammen (Referenz, iNat,
  /// etc.).
  ///
  /// [download]: true → fehlende Bilder werden heruntergeladen.
  ///             false → nur bereits vorhandene lokale Dateien werden verwendet.
  Future<SpeciesWithLocalImages> resolve(
    Species species,
    List<Picture> pictures, {
    bool download = true,
  }) async {
    final urlToLocalPath = download
        ? await _downloadPicturesByOrigin(pictures)
        : await _resolvePicturesByOrigin(pictures);

    final localPictures = pictures
        .map((picture) {
          if (picture.url != null && urlToLocalPath.containsKey(picture.url)) {
            return LocalPicture(picture, urlToLocalPath[picture.url]!);
          }
          return null;
        })
        .whereType<LocalPicture>()
        .toList();

    return SpeciesWithLocalImages(
      _copySpeciesWithPictures(species, pictures),
      localPictures,
    );
  }

  Future<SpeciesWithLocalImages> resolveEnsuringSingleImage(
    Species species,
    List<Picture> pictures,
  ) async {
    final resolved = await resolve(species, pictures, download: false);
    if (resolved.localPictures.isNotEmpty) {
      return resolved;
    }

    final firstDownloadablePicture = pictures.firstWhere(
      (picture) => picture.url != null && picture.url!.isNotEmpty,
      orElse: () => const Picture(id: '', species: '', origin: '', isUsable: 0),
    );
    final url = firstDownloadablePicture.url;
    if (url == null || url.isEmpty) {
      return resolved;
    }

    final storageDirectory = _isExternalPicture(firstDownloadablePicture)
        ? _externalImagesDirectory
        : _referenceImagesDirectory;
    final downloaded = await _imageService.downloadAndSaveUrlMap(
      {url},
      storageDirectory: storageDirectory,
      skipIfHostCoolingDown: true,
    );
    if (!downloaded.containsKey(url)) {
      return resolved;
    }

    return resolve(species, pictures, download: false);
  }

  Future<Map<String, String>> _downloadPicturesByOrigin(
    List<Picture> pictures,
  ) async {
    final referenceUrls = <String>{};
    final externalUrls = <String>{};

    for (final picture in pictures) {
      final url = picture.url;
      if (url == null || url.isEmpty) continue;
      if (_isExternalPicture(picture)) {
        externalUrls.add(url);
      } else {
        referenceUrls.add(url);
      }
    }

    final referencePaths = await _imageService.downloadAndSaveUrlMap(
      referenceUrls,
      storageDirectory: _referenceImagesDirectory,
    );
    final externalPaths = await _imageService.downloadAndSaveUrlMap(
      externalUrls,
      storageDirectory: _externalImagesDirectory,
      // External pictures are dominated by iNaturalist-hosted media. Keep
      // those downloads serial to respect iNaturalist rate limits; reference
      // images still use the default parallel path.
      maxConcurrent: 1,
    );

    return {...referencePaths, ...externalPaths};
  }

  Future<Map<String, String>> _resolvePicturesByOrigin(
    List<Picture> pictures,
  ) async {
    final referenceUrls = <String>{};
    final externalUrls = <String>{};

    for (final picture in pictures) {
      final url = picture.url;
      if (url == null || url.isEmpty) continue;
      if (_isExternalPicture(picture)) {
        externalUrls.add(url);
      } else {
        referenceUrls.add(url);
      }
    }

    final referencePaths = await _imageService.resolveSavedUrlMap(
      referenceUrls,
      storageDirectory: _referenceImagesDirectory,
    );
    final externalPaths = await _imageService.resolveSavedUrlMap(
      externalUrls,
      storageDirectory: _externalImagesDirectory,
      legacyDirectories: const {_referenceImagesDirectory},
    );

    return {...referencePaths, ...externalPaths};
  }

  bool _isExternalPicture(Picture picture) {
    return picture.origin.toLowerCase() == 'inaturalist';
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
      maxLengthCm: species.maxLengthCm,
      depthMinM: species.depthMinM,
      depthMaxM: species.depthMaxM,
      habitat: species.habitat,
      habitatTag: species.habitatTag,
      conservation: species.conservation,
      dangerousToHumansRaw: species.dangerousToHumansRaw,
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
}
