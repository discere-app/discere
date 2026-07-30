import 'package:discere/catalog/model/external_id_provider.dart';
import 'package:discere/catalog/model/picture.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/repository/external_id_cache_repository.dart';
import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/enrichment/pipeline/mapper/inaturalist_photo_picture_mapper.dart';
import 'package:discere/enrichment/pipeline/model/import_enrichment_summary.dart';
import 'package:discere/enrichment/pipeline/repository/inat_photo_cache_repository.dart';
import 'package:discere/enrichment/pipeline/service/inat_taxon_resolver.dart';
import 'package:discere/external/inaturalist/inaturalist_service.dart';
import 'package:discere/external/inaturalist/models/inat_photo.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:discere/shared/util/concurrency_utils.dart';
import 'package:discere/shared/util/logger.dart';

/// Fetches iNaturalist photos for species — both the primary fetch (a
/// species' first photo(s), tried once it has no usable reference image)
/// and backfill (additional photos for a species beyond the first). Both
/// capabilities in the producer-consumer pipeline are driven exclusively by
/// `INatWorker`, one species at a time.
class INatPhotoEnrichmentService {
  static final _log = Logger.forType(INatPhotoEnrichmentService);
  static const _maxConcurrentFetches = 3;
  static const _externalImagesDirectory = 'external_images';
  // iNaturalist image downloads are intentionally serialized. The API/host is
  // comparatively rate-limit sensitive, and parallel image fetches there did
  // not produce meaningful throughput gains in practice. Keeping external
  // image downloads at 1 reduces heat, network bursts, and repeated retries.
  static const _maxConcurrentImageDownloads = 1;

  final SpeciesRepository _speciesRepository;
  final INaturalistService _iNatService;
  final INatPhotoCacheRepository _iNatCacheRepository;
  final ImageService _imageService;
  final ExternalIdCacheRepository _externalIdCacheRepository;
  final INatTaxonResolver _taxonResolver;
  final InaturalistPhotoPictureMapper _photoPictureMapper;

  const INatPhotoEnrichmentService(
    this._speciesRepository,
    this._iNatService,
    this._iNatCacheRepository,
    this._imageService,
    this._externalIdCacheRepository,
    this._taxonResolver, {
    InaturalistPhotoPictureMapper photoPictureMapper =
        const InaturalistPhotoPictureMapper(),
  }) : _photoPictureMapper = photoPictureMapper;

  /// Fetches iNaturalist photos for all given species.
  ///
  /// Important queue contract:
  /// [onSpeciesCompleted] is only fired once a species reached a terminal state
  /// for this capability. A terminal state is either:
  /// - photos were fetched, persisted, and at least one was actually
  ///   downloaded to local storage, or
  /// - the iNat photo cache now contains an explicit empty sentinel because the
  ///   taxon was resolved but iNat has no usable photos.
  ///
  /// We intentionally do not call [onSpeciesCompleted] for transient failures,
  /// unresolved lookups, or a photo download that silently failed (known URL,
  /// no local file) — a UI (e.g. the flashcard review session) that only
  /// checks image-completeness must never see a species treated as "done"
  /// while it still has no local image.
  Future<ImportEnrichmentSummary> fetchINatPhotosForSpecies(
    Set<String> speciesIds, {
    void Function(String speciesId)? onSpeciesCompleted,
    bool primaryOnly = false,
  }) async {
    if (speciesIds.isEmpty) {
      return ImportEnrichmentSummary.empty;
    }

    final speciesList = (await _speciesRepository.getSpecies(
      speciesIds,
    )).toList();
    final primaryQueue = await _buildPrimaryINatPhotoQueue(speciesList);
    final candidates = primaryQueue.candidates;
    final preResolvedTaxonIds = await _taxonResolver.batchResolveKnownTaxonIds(
      candidates,
    );
    if (preResolvedTaxonIds.isNotEmpty) {
      await _iNatService.prefetchTaxonDetails(preResolvedTaxonIds.values);
    }

    var enrichedCount = 0;
    var imageCount = 0;

    // Primary iNat enrichment can be reclaimed for a species that has since
    // reached a terminal cache state elsewhere (for example via another deck
    // or a foreground single-species fetch). Those species must be marked
    // complete immediately, otherwise the caller keeps reclaiming the same
    // species without any network work.
    for (final speciesId in primaryQueue.terminalSpeciesIds) {
      onSpeciesCompleted?.call(speciesId);
    }

    await runConcurrently<Species>(
      candidates,
      maxConcurrent: _maxConcurrentFetches,
      task: (species) async {
        try {
          final outcome = await _fetchAndPersistINatPictures(
            species,
            taxonId: preResolvedTaxonIds[species.id],
            maxPhotos: primaryOnly ? 1 : 10,
          );

          var downloadSucceeded = true;
          if (outcome.pictures.isNotEmpty) {
            enrichedCount++;
            imageCount += _picturesByUrl(outcome.pictures).length;
            final downloaded = await _imageService.downloadAndSaveUrlMap(
              _picturesByUrl(outcome.pictures).keys.toSet(),
              storageDirectory: _externalImagesDirectory,
              // Reference images may stay parallel, but iNaturalist-hosted
              // media is deliberately fetched one-by-one to stay friendly to
              // iNaturalist's rate limits and avoid local resource spikes.
              maxConcurrent: _maxConcurrentImageDownloads,
            );
            downloadSucceeded = downloaded.isNotEmpty;
          }
          // A species with known photo URLs whose download failed must stay
          // pending and retry — the flashcard UI needs the local file, not
          // just cached metadata. See downloadBaseImagesForSpecies for the
          // same reasoning.
          if (outcome.isTerminal && downloadSucceeded) {
            onSpeciesCompleted?.call(species.id);
          }
        } catch (e) {
          _log.warn('iNat photo fetch failed for ${species.id}: $e');
        }
      },
    );

    return ImportEnrichmentSummary(
      imageSpeciesCount: enrichedCount,
      imageCount: imageCount,
      commonNameSpeciesCount: 0,
      commonNameCount: 0,
    );
  }

  Future<ImportEnrichmentSummary> backfillINatPhotosForSpecies(
    Set<String> speciesIds, {
    void Function(String speciesId)? onSpeciesCompleted,
    int targetPhotoCount = 10,
  }) async {
    if (speciesIds.isEmpty) {
      return ImportEnrichmentSummary.empty;
    }

    final speciesList = (await _speciesRepository.getSpecies(
      speciesIds,
    )).toList();
    final backfillQueue = await _buildBackfillINatPhotoQueue(
      speciesList,
      targetPhotoCount: targetPhotoCount,
    );
    final candidates = backfillQueue.candidates;
    final preResolvedTaxonIds = await _taxonResolver.batchResolveKnownTaxonIds(
      candidates,
    );
    if (preResolvedTaxonIds.isNotEmpty) {
      await _iNatService.prefetchTaxonDetails(preResolvedTaxonIds.values);
    }

    var enrichedCount = 0;
    var imageCount = 0;

    // Backfill has two terminal skip states that should not be retried:
    // species with an explicit empty iNat-photo sentinel and species that
    // already reached the desired photo count. Marking them complete here
    // prevents reclaim loops that keep reclaiming the same species without
    // making any further network progress.
    for (final speciesId in backfillQueue.terminalSpeciesIds) {
      onSpeciesCompleted?.call(speciesId);
    }

    if (candidates.isEmpty) {
      return ImportEnrichmentSummary.empty;
    }

    await runConcurrently<Species>(
      candidates,
      maxConcurrent: _maxConcurrentFetches,
      task: (species) async {
        try {
          final outcome = await _fetchAndPersistINatPictures(
            species,
            taxonId: preResolvedTaxonIds[species.id],
            maxPhotos: targetPhotoCount,
            allowTier3Fallback: true,
          );

          var downloadSucceeded = true;
          if (outcome.pictures.isNotEmpty) {
            enrichedCount++;
            imageCount += _picturesByUrl(outcome.pictures).length;
            final downloaded = await _imageService.downloadAndSaveUrlMap(
              _picturesByUrl(outcome.pictures).keys.toSet(),
              storageDirectory: _externalImagesDirectory,
              // Backfill uses the same serialized iNaturalist image policy as
              // primary enrichment. The deck can take longer, but it avoids
              // parallel bursts against iNaturalist with little real benefit.
              maxConcurrent: _maxConcurrentImageDownloads,
            );
            downloadSucceeded = downloaded.isNotEmpty;
          }
          if (outcome.isTerminal && downloadSucceeded) {
            onSpeciesCompleted?.call(species.id);
          }
        } catch (e) {
          _log.warn('iNat backfill failed for ${species.id}: $e');
        }
      },
    );

    return ImportEnrichmentSummary(
      imageSpeciesCount: enrichedCount,
      imageCount: imageCount,
      commonNameSpeciesCount: 0,
      commonNameCount: 0,
    );
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  /// Stores the taxon's Wikipedia URL, reusing the generic external-ID cache
  /// rather than a dedicated table.
  Future<void> _persistWikipediaUrl(
    Species species,
    String? wikipediaUrl,
  ) async {
    if (wikipediaUrl == null || wikipediaUrl.isEmpty) return;
    await _externalIdCacheRepository.saveExternalId(
      species.id,
      ExternalIdProvider.wikipedia,
      wikipediaUrl,
    );
  }

  /// Stores the taxon's IUCN Red List status code, reusing the generic
  /// external-ID cache rather than a dedicated table (same reasoning as
  /// [_persistWikipediaUrl]).
  Future<void> _persistIucnStatus(Species species, String? iucnStatus) async {
    if (iucnStatus == null || iucnStatus.isEmpty) return;
    await _externalIdCacheRepository.saveExternalId(
      species.id,
      ExternalIdProvider.iucnStatus,
      iucnStatus,
    );
  }

  /// Returns whether the species reached a terminal photo-enrichment outcome.
  ///
  /// A terminal empty result is still meaningful here because
  /// [INatPhotoCacheRepository.cachePhotos] stores an explicit empty sentinel.
  Future<_SpeciesPhotoFetchOutcome> _fetchAndPersistINatPictures(
    Species species, {
    int? taxonId,
    int maxPhotos = 10,
    bool allowTier3Fallback = false,
  }) async {
    ({
      int taxonId,
      List<INatPhoto> photos,
      String? wikipediaUrl,
      String? iucnStatus,
    })?
    result;
    try {
      result = await _fetchPhotosWithScientificNameFallback(
        species,
        taxonId: taxonId,
        maxPhotos: maxPhotos,
        allowTier3Fallback: allowTier3Fallback,
      );
    } on TaxonNotFoundException {
      await _iNatCacheRepository.cachePhotos(species.id, const []);
      return const _SpeciesPhotoFetchOutcome(pictures: [], isTerminal: true);
    }
    if (result == null) {
      return const _SpeciesPhotoFetchOutcome(pictures: [], isTerminal: false);
    }

    await _taxonResolver.persistResolvedTaxonId(
      species,
      previousTaxonId: taxonId,
      resolvedTaxonId: result.taxonId,
    );
    await _persistWikipediaUrl(species, result.wikipediaUrl);
    await _persistIucnStatus(species, result.iucnStatus);
    await _iNatCacheRepository.cachePhotos(species.id, result.photos);
    return _SpeciesPhotoFetchOutcome(
      pictures: _photoPictureMapper.map(species.id, result.photos),
      isTerminal: true,
    );
  }

  Future<({List<Species> candidates, Set<String> terminalSpeciesIds})>
  _buildPrimaryINatPhotoQueue(List<Species> speciesList) async {
    final candidates = <Species>[];
    final terminalSpeciesIds = <String>{};

    for (final species in speciesList) {
      final cachedPhotos = await _iNatCacheRepository.getCachedPhotos(
        species.id,
      );
      if (cachedPhotos != null) {
        terminalSpeciesIds.add(species.id);
        continue;
      }
      candidates.add(species);
    }

    candidates.sort(
      (a, b) => a.getBinomialName().compareTo(b.getBinomialName()),
    );

    return (candidates: candidates, terminalSpeciesIds: terminalSpeciesIds);
  }

  Future<({List<Species> candidates, Set<String> terminalSpeciesIds})>
  _buildBackfillINatPhotoQueue(
    List<Species> speciesList, {
    int targetPhotoCount = 10,
  }) async {
    final candidates = <({Species species, int cachedPhotoCount})>[];
    final terminalSpeciesIds = <String>{};

    for (final species in speciesList) {
      final cachedPhotos = await _iNatCacheRepository.getCachedPhotos(
        species.id,
      );
      // A `null` cache entry means this species has never been looked up on
      // iNaturalist at all yet (e.g. it already had a usable reference image
      // and so was never routed through primary iNat enrichment) — treat
      // that as "0 cached photos, worth fetching" rather than skipping it,
      // otherwise a species that only ever reaches backfill would never get
      // a terminal outcome here. An explicit empty list, by contrast, means
      // iNat was already checked and confirmed to have nothing — that stays
      // terminal, no point re-checking.
      if (cachedPhotos != null &&
          (cachedPhotos.isEmpty || cachedPhotos.length >= targetPhotoCount)) {
        terminalSpeciesIds.add(species.id);
        continue;
      }

      candidates.add((
        species: species,
        cachedPhotoCount: cachedPhotos?.length ?? 0,
      ));
    }

    candidates.sort((a, b) {
      final photoCountComparison = a.cachedPhotoCount.compareTo(
        b.cachedPhotoCount,
      );
      if (photoCountComparison != 0) return photoCountComparison;
      return a.species.getBinomialName().compareTo(b.species.getBinomialName());
    });

    return (
      candidates: candidates.map((entry) => entry.species).toList(),
      terminalSpeciesIds: terminalSpeciesIds,
    );
  }

  Future<
    ({
      int taxonId,
      List<INatPhoto> photos,
      String? wikipediaUrl,
      String? iucnStatus,
    })?
  >
  _fetchPhotosWithScientificNameFallback(
    Species species, {
    required int? taxonId,
    required int maxPhotos,
    bool allowTier3Fallback = false,
  }) async {
    if (taxonId != null) {
      return _iNatService.fetchPhotos(
        species.getBinomialName(),
        taxonId: taxonId,
        maxPhotos: maxPhotos,
        allowTier3Fallback: allowTier3Fallback,
      );
    }

    // Only conclude the species is genuinely unresolvable (as opposed to a
    // transient failure worth retrying later) if every candidate name was
    // definitively rejected by iNaturalist rather than merely failing.
    var allCandidatesNotFound = true;
    for (final candidate in await _taxonResolver.scientificNameCandidates(
      species,
    )) {
      try {
        final result = await _iNatService.fetchPhotos(
          candidate,
          maxPhotos: maxPhotos,
          allowTier3Fallback: allowTier3Fallback,
        );
        if (result == null) {
          allCandidatesNotFound = false;
          continue;
        }
        if (candidate != species.getBinomialName()) {
          _log.debug(
            'iNat photo fallback matched ${species.id}: '
            '${species.getBinomialName()} -> $candidate '
            '(taxon=${result.taxonId})',
          );
        }
        return result;
      } on TaxonNotFoundException {
        continue;
      }
    }

    if (allCandidatesNotFound) {
      throw TaxonNotFoundException(species.getBinomialName());
    }
    return null;
  }

  Map<String, Picture> _picturesByUrl(Iterable<Picture> pictures) {
    final picturesByUrl = <String, Picture>{};
    for (final picture in pictures) {
      final url = picture.url;
      if (url == null || url.isEmpty) continue;
      picturesByUrl.putIfAbsent(url, () => picture);
    }
    return picturesByUrl;
  }
}

class _SpeciesPhotoFetchOutcome {
  final List<Picture> pictures;
  final bool isTerminal;

  const _SpeciesPhotoFetchOutcome({
    required this.pictures,
    required this.isTerminal,
  });
}
