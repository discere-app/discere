import 'package:discere/catalog/model/picture.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/shared/service/image_service.dart';

/// A species together with the pictures to resolve for it — the unit
/// [LocalSpeciesImageService.resolveAll] works on, since which pictures a
/// species shows is decided above it (reference pictures plus whatever the
/// iNaturalist cache holds) rather than read off the species itself.
typedef SpeciesPictures = ({Species species, List<Picture> pictures});

/// Resolves a species' pictures to files on disk, downloading what is
/// missing.
///
/// Lives in `enrichment/media/` rather than with the catalog models it takes
/// and returns, because what it knows is media acquisition, not taxonomy:
/// where species images are stored, and that iNaturalist-hosted ones need
/// their own directory and serial downloads to stay inside that host's rate
/// limits. Both directories it writes to are filled by enrichment's own
/// workers — `BaseWorker` for reference images, `INatWorker` for the rest.
class LocalSpeciesImageService {
  static const _referenceImagesDirectory = 'reference_images';
  static const _externalImagesDirectory = 'external_images';

  final ImageService _imageService;

  const LocalSpeciesImageService(this._imageService);

  /// Resolves [pictures] to local file paths and returns
  /// [SpeciesWithLocalImages]. Does not distinguish where the pictures come
  /// from (reference, iNat, etc.).
  ///
  /// [download]: true → missing images are downloaded.
  ///             false → only local files that already exist are used.
  Future<SpeciesWithLocalImages> resolve(
    Species species,
    List<Picture> pictures, {
    bool download = true,
  }) async {
    final resolved = await resolveAll([
      (species: species, pictures: pictures),
    ], download: download);
    return resolved.single;
  }

  /// Like [resolve] for several species, whose images are resolved (or, with
  /// [download], downloaded) in a single pass: one path resolution for all
  /// URLs together instead of one per species.
  Future<List<SpeciesWithLocalImages>> resolveAll(
    List<SpeciesPictures> entries, {
    bool download = true,
  }) async {
    final allPictures = entries
        .expand((entry) => entry.pictures)
        .toList(growable: false);
    final urlToLocalPath = download
        ? await _downloadPicturesByOrigin(allPictures)
        : await resolveLocalPaths(allPictures);

    return entries
        .map(
          (entry) => SpeciesWithLocalImages(
            _copySpeciesWithPictures(entry.species, entry.pictures),
            _localPicturesOf(entry.pictures, urlToLocalPath),
          ),
        )
        .toList();
  }

  List<LocalPicture> _localPicturesOf(
    List<Picture> pictures,
    Map<String, String> urlToLocalPath,
  ) {
    return pictures
        .map((picture) {
          final localPath = urlToLocalPath[picture.url];
          return localPath == null ? null : LocalPicture(picture, localPath);
        })
        .whereType<LocalPicture>()
        .toList();
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
    final (reference: referenceUrls, external: externalUrls) = _urlsByOrigin(
      pictures,
    );

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

  /// The local file paths for [pictures], keyed by URL and resolved
  /// separately per storage location (see the class doc). Downloads nothing;
  /// a missing file is simply absent from the result — enough for callers
  /// that only need to know whether an image is on disk.
  Future<Map<String, String>> resolveLocalPaths(List<Picture> pictures) async {
    final (reference: referenceUrls, external: externalUrls) = _urlsByOrigin(
      pictures,
    );

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

  /// The image URLs from [pictures], split by storage location: iNat images
  /// live in their own directory and are downloaded differently from
  /// reference images (see the class doc).
  ({Set<String> reference, Set<String> external}) _urlsByOrigin(
    List<Picture> pictures,
  ) {
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

    return (reference: referenceUrls, external: externalUrls);
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
