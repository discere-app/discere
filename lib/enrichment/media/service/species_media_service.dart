import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/enrichment/media/service/local_species_image_service.dart';
import 'package:discere/enrichment/media/service/species_photo_service.dart';

/// Orchestrates [SpeciesPhotoService] and [LocalSpeciesImageService] for
/// UI-side use cases, and is the entry point for species media from outside
/// this folder.
class SpeciesMediaService {
  final SpeciesRepository _speciesRepository;
  final SpeciesPhotoService _speciesPhotoService;
  final LocalSpeciesImageService _localSpeciesImageService;

  const SpeciesMediaService(
    this._speciesRepository,
    this._speciesPhotoService,
    this._localSpeciesImageService,
  );

  /// Returns the species with its locally cached images. No network access,
  /// no download of missing images — fast enough for the initial render.
  Future<SpeciesWithLocalImages?> resolveFromCache(String speciesId) async {
    final species = await _speciesRepository.getSpeciesById(speciesId);
    if (species == null) return null;
    final pictures = await _speciesPhotoService.getPhotos(species);
    return _localSpeciesImageService.resolve(
      species,
      pictures,
      download: false,
    );
  }

  /// Like [resolveFromCache] for several species, but with one bundled
  /// species load, one bundled photo-cache read and one bundled path
  /// resolution: the cost scales with the number of queries, not with the
  /// number of species. This is the path a review session resolves its due
  /// cards through, and the one a list gets its first render from.
  Future<List<SpeciesWithLocalImages>> resolveAllFromCache(
    Set<String> speciesIds,
  ) => _resolveAll(speciesIds, download: false);

  /// Like [resolveAllFromCache], but downloads missing images — in a single
  /// pass for the whole set, not one per species. The external (iNaturalist)
  /// downloads within it run strictly serially, as the rate-limit rule in
  /// [LocalSpeciesImageService] requires. That costs nothing here, because no
  /// screen waits on this call: a list use case renders from
  /// [resolveAllFromCache] and takes over this result once it arrives.
  Future<List<SpeciesWithLocalImages>> resolveAllWithDownload(
    Set<String> speciesIds,
  ) => _resolveAll(speciesIds, download: true);

  /// Like [resolveAllFromCache] for a caller that already holds its species:
  /// the species load with its joins is skipped, leaving the bundled
  /// photo-cache read and the bundled path resolution. The result follows the
  /// order of [species].
  ///
  /// [species] must be passed as the species load returns them, i.e. with
  /// only their reference pictures. The species in a result already carry
  /// the iNat photos in their `pictures`; passing them back in here yields
  /// every iNat photo twice.
  Future<List<SpeciesWithLocalImages>> resolveSpeciesFromCache(
    List<Species> species,
  ) => _resolveSpecies(species, download: false);

  Future<List<SpeciesWithLocalImages>> _resolveAll(
    Set<String> speciesIds, {
    required bool download,
  }) async {
    if (speciesIds.isEmpty) return [];
    final speciesById = {
      for (final species in await _speciesRepository.getSpecies(speciesIds))
        species.id: species,
    };

    // In request order, not in the species load's taxonomic order: a list
    // shows its entries the way the caller passes them in. And because both
    // variants return the same order, a caller can render from the cache
    // first and take over the download result later without the list
    // reordering itself.
    final ordered = speciesIds
        .map((id) => speciesById[id])
        .whereType<Species>()
        .toList();

    return _resolveSpecies(ordered, download: download);
  }

  /// The shared core of all bundled resolutions: one photo-cache read and
  /// one path resolution for the whole list, in its order.
  Future<List<SpeciesWithLocalImages>> _resolveSpecies(
    List<Species> species, {
    required bool download,
  }) async {
    if (species.isEmpty) return [];
    final picturesBySpeciesId = await _speciesPhotoService.getPhotosBySpeciesId(
      species,
    );

    return _localSpeciesImageService.resolveAll([
      for (final entry in species)
        (species: entry, pictures: picturesBySpeciesId[entry.id]!),
    ], download: download);
  }

  /// Like [resolveFromCache], but fetches live from iNat when there is no
  /// cache entry. Used for the iNat refresh on the species detail page.
  Future<SpeciesWithLocalImages?> resolveWithFetch(String speciesId) async {
    final species = await _speciesRepository.getSpeciesById(speciesId);
    if (species == null) return null;
    final pictures = await _speciesPhotoService.getPhotosWithFallback(species);
    return _localSpeciesImageService.resolve(
      species,
      pictures,
      download: false,
    );
  }

  /// Returns cached media immediately and downloads at most one missing image
  /// for the currently focused flashcard when needed.
  Future<SpeciesWithLocalImages?> resolveEnsuringSingleImage(
    String speciesId,
  ) async {
    final species = await _speciesRepository.getSpeciesById(speciesId);
    if (species == null) return null;
    final pictures = await _speciesPhotoService.getPhotos(species);
    return _localSpeciesImageService.resolveEnsuringSingleImage(
      species,
      pictures,
    );
  }

  /// The species from [speciesIds] that have no image file on disk.
  ///
  /// Answers only that question and does not load the species for it: the
  /// candidate URLs — usable reference pictures plus the rows in the iNat
  /// cache — and one bundled path resolution are enough. Both are indexed
  /// batch queries without joins, whereas the full [Species] with joins,
  /// common names, traits and regions costs many times as much.
  ///
  /// Whether "not on disk" also means "does not exist" is for the caller to
  /// decide: only once a deck's image stages have finished is a missing image
  /// a gap rather than merely not downloaded yet.
  Future<Set<String>> findSpeciesWithoutLocalImage(
    Set<String> speciesIds,
  ) async {
    if (speciesIds.isEmpty) return const {};
    final referencePictures = await _speciesRepository.getPicturesBySpeciesId(
      speciesIds,
    );
    final cachedPhotos = await _speciesPhotoService.getCachedPhotosBySpeciesId(
      speciesIds,
    );
    final candidatesBySpeciesId = {
      for (final speciesId in speciesIds)
        speciesId: [
          ...?referencePictures[speciesId],
          ...?cachedPhotos[speciesId],
        ],
    };

    final localPaths = await _localSpeciesImageService.resolveLocalPaths(
      candidatesBySpeciesId.values.expand((pictures) => pictures).toList(),
    );

    return {
      for (final entry in candidatesBySpeciesId.entries)
        if (!entry.value.any(
          (picture) => localPaths.containsKey(picture.url),
        ))
          entry.key,
    };
  }

  /// Whether an iNat cache entry exists for the species. Used by the species
  /// detail page to decide whether to trigger an iNat fetch.
  Future<bool> hasEnrichedPhotos(String speciesId) {
    return _speciesPhotoService.hasCachedPhotos(speciesId);
  }
}
