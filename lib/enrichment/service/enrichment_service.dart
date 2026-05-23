import 'package:discere/enrichment/mapper/inaturalist_photo_picture_mapper.dart';
import 'package:discere/enrichment/model/enrichment_work_plan.dart';
import 'package:discere/shared/external/inaturalist_service.dart';
import 'package:discere/shared/external/models/inat_common_name.dart';
import 'package:discere/shared/external/models/inat_photo.dart';
import 'package:discere/catalog/model/picture.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/catalog/repository/external_id_cache_repository.dart';
import 'package:discere/catalog/repository/external_id_repository.dart';
import 'package:discere/enrichment/repository/inat_photo_cache_repository.dart';
import 'package:discere/enrichment/repository/runtime_common_name_repository.dart';
import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:discere/shared/util/concurrency_utils.dart';
import 'package:discere/shared/util/logger.dart';

/// Collects the outcome of post-import deck enrichment.
///
/// The import flow can enrich decks with local reference images,
/// iNaturalist photos, and multilingual common names. This value object keeps
/// the combined counts in one place so the UI can render a single summary.
class ImportEnrichmentSummary {
  final int imageSpeciesCount;
  final int imageCount;
  final int commonNameSpeciesCount;
  final int commonNameCount;

  const ImportEnrichmentSummary({
    required this.imageSpeciesCount,
    required this.imageCount,
    required this.commonNameSpeciesCount,
    required this.commonNameCount,
  });

  static const empty = ImportEnrichmentSummary(
    imageSpeciesCount: 0,
    imageCount: 0,
    commonNameSpeciesCount: 0,
    commonNameCount: 0,
  );

  ImportEnrichmentSummary operator +(ImportEnrichmentSummary other) {
    return ImportEnrichmentSummary(
      imageSpeciesCount: imageSpeciesCount + other.imageSpeciesCount,
      imageCount: imageCount + other.imageCount,
      commonNameSpeciesCount:
          commonNameSpeciesCount + other.commonNameSpeciesCount,
      commonNameCount: commonNameCount + other.commonNameCount,
    );
  }
}

class CommonNameStageDiagnostics {
  final Set<String> speciesIdsWithRemainingErrors;

  const CommonNameStageDiagnostics({
    this.speciesIdsWithRemainingErrors = const <String>{},
  });
}

class TaxonomyCommonNameDiagnostics {
  final Set<String> failedEntityKeys;
  final Set<String> speciesIdsWithRemainingErrors;

  const TaxonomyCommonNameDiagnostics({
    this.failedEntityKeys = const <String>{},
    this.speciesIdsWithRemainingErrors = const <String>{},
  });
}

/// Coordinates post-import enrichment of deck species with iNaturalist
/// photos and multilingual common names.
class EnrichmentService {
  static final _log = Logger.forType(EnrichmentService);
  static const _maxConcurrentINatSpeciesFetches = 3;
  // iNaturalist image downloads are intentionally serialized. The API/host is
  // comparatively rate-limit sensitive, and parallel image fetches there did
  // not produce meaningful throughput gains in practice. Keeping external
  // image downloads at 1 reduces heat, network bursts, and repeated retries.
  static const _maxConcurrentINatImageDownloads = 1;
  static const _referenceImagesDirectory = 'reference_images';
  static const _externalImagesDirectory = 'external_images';

  final SpeciesRepository _speciesRepository;
  final ImageService _imageService;
  final INaturalistService _iNatService;
  final INatPhotoCacheRepository _iNatCacheRepository;
  final RuntimeCommonNameRepository _runtimeCommonNameRepository;
  final ExternalIdRepository _externalIdRepository;
  final ExternalIdCacheRepository _externalIdCacheRepository;
  final InaturalistPhotoPictureMapper _photoPictureMapper;

  EnrichmentService(
    this._speciesRepository,
    this._imageService,
    this._iNatService,
    this._iNatCacheRepository,
    this._externalIdRepository,
    this._externalIdCacheRepository, {
    RuntimeCommonNameRepository? runtimeCommonNameRepository,
    InaturalistPhotoPictureMapper? photoPictureMapper,
  }) : _runtimeCommonNameRepository =
           runtimeCommonNameRepository ?? RuntimeCommonNameRepository(),
       _photoPictureMapper =
           photoPictureMapper ?? const InaturalistPhotoPictureMapper();

  /// Downloads all reference images (FishBase/SLB) for a list of decks that
  /// aren't already local.
  Future<ImportEnrichmentSummary> downloadBaseImagesForSpecies(
    Set<String> speciesIds, {
    void Function(int completed, int total)? onProgress,
    void Function(String speciesId)? onSpeciesCompleted,
    bool Function()? isCancelled,
  }) async {
    if (speciesIds.isEmpty) {
      onProgress?.call(0, 0);
      return ImportEnrichmentSummary.empty;
    }

    final speciesSet = await _speciesRepository.getSpecies(speciesIds);
    final speciesList = speciesSet.toList();
    final total = speciesList.length;
    var completed = 0;
    var speciesWithImages = 0;
    var imageCount = 0;

    onProgress?.call(0, total);

    await runConcurrently<Species>(
      speciesList,
      maxConcurrent: _maxConcurrentINatSpeciesFetches,
      isCancelled: isCancelled,
      task: (species) async {
        try {
          final picturesByUrl = _picturesByUrl(species.pictures);
          if (picturesByUrl.isNotEmpty) {
            await _imageService.downloadAndSaveUrlMap(
              picturesByUrl.keys.toSet(),
              storageDirectory: _referenceImagesDirectory,
            );
            speciesWithImages++;
            imageCount += picturesByUrl.length;
          }
        } catch (_) {
          // Keep going so one broken species image set does not block the deck.
        } finally {
          completed++;
          onSpeciesCompleted?.call(species.id);
          onProgress?.call(completed, total);
        }
      },
    );

    return ImportEnrichmentSummary(
      imageSpeciesCount: speciesWithImages,
      imageCount: imageCount,
      commonNameSpeciesCount: 0,
      commonNameCount: 0,
    );
  }

  /// Fetches iNaturalist photos for all species in the given decks.
  ///
  /// Call this after deck creation/import, with user consent.
  ///
  /// Important queue contract:
  /// [onSpeciesCompleted] is only fired once a species reached a terminal state
  /// for this stage. A terminal state is either:
  /// - photos were fetched and persisted successfully, or
  /// - the iNat photo cache now contains an explicit empty sentinel because the
  ///   taxon was resolved but iNat has no usable photos.
  ///
  /// We intentionally do not call [onSpeciesCompleted] for transient failures
  /// or unresolved lookups. That allows the queue checkpointing logic to keep
  /// the species in `remainingSpeciesIdsByStage` instead of falsely marking the
  /// whole stage as complete.
  ///
  /// [onProgress] is called with (completed, total) for image download progress.
  /// Returns a summary of how many species and images were downloaded.
  Future<ImportEnrichmentSummary> fetchINatPhotosForSpecies(
    Set<String> speciesIds, {
    void Function(int completed, int total)? onProgress,
    void Function(String speciesId)? onSpeciesCompleted,
    bool force = false,
    bool primaryOnly = false,
    bool prioritizeSpeciesWithoutImages = false,
    int maxConcurrent = _maxConcurrentINatSpeciesFetches,
    Duration? requestSpacing,
    bool Function()? isCancelled,
  }) async {
    if (speciesIds.isEmpty) {
      onProgress?.call(0, 0);
      return ImportEnrichmentSummary.empty;
    }

    final speciesList = (await _speciesRepository.getSpecies(
      speciesIds,
    )).toList();
    final primaryQueue = await _buildPrimaryINatPhotoQueue(
      speciesList,
      force: force,
      prioritizeSpeciesWithoutImages: prioritizeSpeciesWithoutImages,
    );
    final candidates = primaryQueue.candidates;
    final preResolvedTaxonIds = await _batchResolveKnownTaxonIds(candidates);
    if (preResolvedTaxonIds.isNotEmpty) {
      await _iNatService.prefetchTaxonDetails(preResolvedTaxonIds.values);
    }
    final terminalSpeciesIds = primaryQueue.terminalSpeciesIds.toList()..sort();
    final total = candidates.length + terminalSpeciesIds.length;
    var completed = 0;
    var enrichedCount = 0;
    var imageCount = 0;

    if (total == 0) {
      onProgress?.call(0, 0);
      return ImportEnrichmentSummary.empty;
    }

    // Primary iNat enrichment can resume against a stage checkpoint that still
    // lists species which have since reached a terminal cache state elsewhere
    // (for example via another deck or a foreground single-species fetch).
    // Those species must be marked complete immediately, otherwise the stage
    // keeps yielding the same remaining set without any network work.
    for (final speciesId in terminalSpeciesIds) {
      onSpeciesCompleted?.call(speciesId);
      completed++;
    }

    onProgress?.call(0, total);

    if (completed > 0) {
      onProgress?.call(completed, total);
    }

    await runThrottled<Species>(
      candidates,
      maxConcurrent: maxConcurrent,
      requestSpacing: requestSpacing,
      isCancelled: isCancelled,
      task: (species) async {
        try {
          final outcome = await _fetchAndPersistINatPictures(
            species,
            taxonId: preResolvedTaxonIds[species.id],
            maxPhotos: primaryOnly ? 1 : 10,
          );

          if (outcome.pictures.isNotEmpty) {
            enrichedCount++;
            imageCount += _picturesByUrl(outcome.pictures).length;
            await _imageService.downloadAndSaveUrlMap(
              _picturesByUrl(outcome.pictures).keys.toSet(),
              storageDirectory: _externalImagesDirectory,
              // Reference images may stay parallel, but iNaturalist-hosted
              // media is deliberately fetched one-by-one to stay friendly to
              // iNaturalist's rate limits and avoid local resource spikes.
              maxConcurrent: _maxConcurrentINatImageDownloads,
            );
          }
          if (outcome.isTerminal) {
            onSpeciesCompleted?.call(species.id);
          }
        } catch (e) {
          _log.warn('iNat photo fetch failed for ${species.id}: $e');
        } finally {
          completed++;
          onProgress?.call(completed, total);
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
    void Function(int completed, int total)? onProgress,
    void Function(String speciesId)? onSpeciesCompleted,
    int targetPhotoCount = 10,
    int maxConcurrent = _maxConcurrentINatSpeciesFetches,
    Duration? requestSpacing,
    bool Function()? isCancelled,
  }) async {
    if (speciesIds.isEmpty) {
      onProgress?.call(0, 0);
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
    final preResolvedTaxonIds = await _batchResolveKnownTaxonIds(candidates);
    if (preResolvedTaxonIds.isNotEmpty) {
      await _iNatService.prefetchTaxonDetails(preResolvedTaxonIds.values);
    }
    final terminalSpeciesIds = backfillQueue.terminalSpeciesIds.toList()
      ..sort();
    final total = candidates.length + terminalSpeciesIds.length;
    var completed = 0;
    var enrichedCount = 0;
    var imageCount = 0;

    if (total == 0) {
      onProgress?.call(0, 0);
      return ImportEnrichmentSummary.empty;
    }

    // Backfill has two terminal skip states that should not be retried:
    // species with an explicit empty iNat-photo sentinel and species that
    // already reached the desired photo count. Marking them complete here
    // prevents checkpoint loops that keep reclaiming the same stage without
    // making any further network progress.
    for (final speciesId in terminalSpeciesIds) {
      onSpeciesCompleted?.call(speciesId);
      completed++;
    }

    onProgress?.call(completed, total);

    if (candidates.isEmpty) {
      return ImportEnrichmentSummary.empty;
    }

    await runThrottled<Species>(
      candidates,
      maxConcurrent: maxConcurrent,
      requestSpacing: requestSpacing,
      isCancelled: isCancelled,
      task: (species) async {
        try {
          final outcome = await _fetchAndPersistINatPictures(
            species,
            taxonId: preResolvedTaxonIds[species.id],
            maxPhotos: targetPhotoCount,
            allowTier3Fallback: true,
          );

          if (outcome.pictures.isNotEmpty) {
            enrichedCount++;
            imageCount += _picturesByUrl(outcome.pictures).length;
            await _imageService.downloadAndSaveUrlMap(
              _picturesByUrl(outcome.pictures).keys.toSet(),
              storageDirectory: _externalImagesDirectory,
              // Backfill uses the same serialized iNaturalist image policy as
              // primary enrichment. The deck can take longer, but it avoids
              // parallel bursts against iNaturalist with little real benefit.
              maxConcurrent: _maxConcurrentINatImageDownloads,
            );
          }
          if (outcome.isTerminal) {
            onSpeciesCompleted?.call(species.id);
          }
        } catch (e) {
          _log.warn('iNat backfill failed for ${species.id}: $e');
        } finally {
          completed++;
          onProgress?.call(completed, total);
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

  Future<ImportEnrichmentSummary> fetchSpeciesCommonNamesForSpecies(
    Set<String> speciesIds, {
    void Function(int completed, int total)? onProgress,
    void Function(String speciesId)? onSpeciesCompleted,
    void Function(CommonNameStageDiagnostics diagnostics)? onDiagnostics,
    bool force = false,
    int maxConcurrent = _maxConcurrentINatSpeciesFetches,
    Duration? requestSpacing,
    bool Function()? isCancelled,
  }) async {
    // Common-name enrichment follows the same terminal-callback contract as
    // photo enrichment. A species only completes the stage when runtime common
    // names were stored or we wrote an explicit no-result marker. Transient
    // lookup failures must leave the species pending so the queue can retry.
    if (speciesIds.isEmpty) {
      onProgress?.call(0, 0);
      return ImportEnrichmentSummary.empty;
    }

    final speciesList = (await _speciesRepository.getSpecies(
      speciesIds,
    )).toList();
    final entitiesWithNames = await _runtimeCommonNameRepository
        .getEntitiesWithStoredOutcome(
          speciesIds.map((speciesId) => _speciesEntityKey(speciesId)).toSet(),
        );
    final knownTaxonIds = await _batchResolveKnownTaxonIds(speciesList);
    // Process species with a known taxon ID first — their common-name fetch
    // goes straight to the API without a live name-resolve round-trip.
    speciesList.sort((a, b) {
      final aKnown = knownTaxonIds.containsKey(a.id) ? 0 : 1;
      final bKnown = knownTaxonIds.containsKey(b.id) ? 0 : 1;
      return aKnown.compareTo(bKnown);
    });
    final total = speciesList.length;
    var completed = 0;
    var enrichedSpeciesCount = 0;
    var commonNameCount = 0;
    final pendingSpeciesCommonNames =
        <Species, Map<String, List<INatCommonName>>>{};

    onProgress?.call(0, total);

    await runThrottled<Species>(
      speciesList,
      maxConcurrent: maxConcurrent,
      requestSpacing: requestSpacing,
      isCancelled: isCancelled,
      task: (species) async {
        try {
          if (!force &&
              entitiesWithNames.contains(_speciesEntityKey(species.id))) {
            onSpeciesCompleted?.call(species.id);
            return;
          }

          final outcome = await _fetchSpeciesCommonNames(
            species,
            taxonId: knownTaxonIds[species.id],
          );
          if (outcome.isTerminal) {
            onSpeciesCompleted?.call(species.id);
          }
          if (outcome.commonNames.isNotEmpty) {
            pendingSpeciesCommonNames[species] = outcome.commonNames;
            enrichedSpeciesCount++;
            commonNameCount += outcome.commonNames.values.fold(
              0,
              (sum, list) => sum + list.length,
            );
          }
        } catch (e) {
          _log.warn('iNat common-name fetch failed for ${species.id}: $e');
        } finally {
          completed++;
          onProgress?.call(completed, total);
        }
      },
    );

    await _runtimeCommonNameRepository.saveSpeciesCommonNamesBatch(
      pendingSpeciesCommonNames,
    );
    if (onDiagnostics != null) {
      onDiagnostics(const CommonNameStageDiagnostics());
    }

    return ImportEnrichmentSummary(
      imageSpeciesCount: 0,
      imageCount: 0,
      commonNameSpeciesCount: enrichedSpeciesCount,
      commonNameCount: commonNameCount,
    );
  }

  Future<ImportEnrichmentSummary> fetchINatTaxonomyCommonNamesForSpecies(
    Set<String> speciesIds, {
    void Function(TaxonomyCommonNameDiagnostics diagnostics)? onDiagnostics,
    bool force = false,
    int maxConcurrent = _maxConcurrentINatSpeciesFetches,
    Duration? requestSpacing,
    bool Function()? isCancelled,
  }) async {
    if (speciesIds.isEmpty) {
      return ImportEnrichmentSummary.empty;
    }
    final workPlan = await buildTaxonomyWorkPlanForSpecies(speciesIds);
    return fetchINatTaxonomyCommonNamesForEntityKeys(
      speciesIds,
      entityKeys: workPlan.map((item) => item.runtimeEntityKey),
      force: force,
      maxConcurrent: maxConcurrent,
      requestSpacing: requestSpacing,
      isCancelled: isCancelled,
      onDiagnostics: onDiagnostics,
    );
  }

  Future<List<TaxonomyWorkPlanItem>> buildTaxonomyWorkPlanForSpecies(
    Set<String> speciesIds,
  ) async {
    if (speciesIds.isEmpty) {
      return const <TaxonomyWorkPlanItem>[];
    }
    final speciesList = (await _speciesRepository.getSpecies(
      speciesIds,
    )).toList();
    final taxonomyTargets = _buildTaxonomyTargets(speciesList);
    final taxonomySpeciesMembership = _buildTaxonomySpeciesMembership(
      speciesList,
    );
    final runtimeEntityKeys = _sortedTaxonomyEntityKeysForSpecies(speciesList);
    final items = <TaxonomyWorkPlanItem>[];
    for (final runtimeEntityKey in runtimeEntityKeys) {
      final target = taxonomyTargets[runtimeEntityKey];
      if (target == null) {
        continue;
      }
      final workKey = await _taxonomyWorkKey(
        runtimeEntityKey: runtimeEntityKey,
        rank: target.rank,
      );
      items.add(
        TaxonomyWorkPlanItem(
          workKey: workKey,
          runtimeEntityKey: runtimeEntityKey,
          rank: target.rank,
          scientificName: target.scientificName,
          speciesIds:
              taxonomySpeciesMembership[runtimeEntityKey] ?? const <String>{},
        ),
      );
    }
    return items;
  }

  Future<ImportEnrichmentSummary> fetchINatTaxonomyCommonNamesForEntityKeys(
    Set<String> speciesIds, {
    required Iterable<String> entityKeys,
    void Function(String entityKey)? onEntityCompleted,
    void Function(TaxonomyCommonNameDiagnostics diagnostics)? onDiagnostics,
    bool force = false,
    int maxConcurrent = _maxConcurrentINatSpeciesFetches,
    Duration? requestSpacing,
    bool Function()? isCancelled,
  }) async {
    if (speciesIds.isEmpty) {
      return ImportEnrichmentSummary.empty;
    }

    final speciesList = (await _speciesRepository.getSpecies(
      speciesIds,
    )).toList();
    final taxonomyTargets = _buildTaxonomyTargets(speciesList);
    final taxonomySpeciesMembership = _buildTaxonomySpeciesMembership(
      speciesList,
    );
    final requestedEntityKeys = _orderedUniqueStrings(
      entityKeys,
    ).where(taxonomyTargets.containsKey).toList(growable: false);
    if (requestedEntityKeys.isEmpty) {
      onDiagnostics?.call(const TaxonomyCommonNameDiagnostics());
      return ImportEnrichmentSummary.empty;
    }

    final entitiesWithNames = await _runtimeCommonNameRepository
        .getEntitiesWithStoredOutcome(requestedEntityKeys.toSet());

    var enrichedEntityCount = 0;
    var commonNameCount = 0;
    final pendingTaxonomyCommonNames = <RuntimeTaxonomyCommonNameRecord>[];
    final failedEntityKeys = <String>{};

    await runThrottled<String>(
      requestedEntityKeys,
      maxConcurrent: maxConcurrent,
      requestSpacing: requestSpacing,
      isCancelled: isCancelled,
      task: (entityKey) async {
        final taxonomyTarget = taxonomyTargets[entityKey]!;
        if (!force && entitiesWithNames.contains(entityKey)) {
          onEntityCompleted?.call(entityKey);
          return;
        }

        try {
          final commonNames = await _fetchTaxonomyCommonNames(
            entityKey: entityKey,
            scientificName: taxonomyTarget.scientificName,
            rank: taxonomyTarget.rank,
          );
          if (commonNames.isEmpty) {
            await _runtimeCommonNameRepository.markNoCommonNames(
              entityKey: entityKey,
              entityType: _entityTypeForTaxonomyRank(taxonomyTarget.rank),
            );
            onEntityCompleted?.call(entityKey);
            return;
          }

          pendingTaxonomyCommonNames.add(
            RuntimeTaxonomyCommonNameRecord(
              entityKey: entityKey,
              entityType: _entityTypeForTaxonomyRank(taxonomyTarget.rank),
              scientificName: taxonomyTarget.scientificName,
              referenceCommonNames: _referenceCommonNamesForTaxonomyTarget(
                speciesList,
                taxonomyTarget.rank,
                taxonomyTarget.scientificName,
              ),
              runtimeCommonNames: commonNames,
            ),
          );
          enrichedEntityCount++;
          commonNameCount += commonNames.values.fold(
            0,
            (sum, list) => sum + list.length,
          );
          onEntityCompleted?.call(entityKey);
        } catch (e) {
          failedEntityKeys.add(entityKey);
          _log.warn(
            'iNat taxonomy common-name fetch failed for $entityKey: $e',
          );
        }
      },
    );

    await _runtimeCommonNameRepository.saveTaxonomyCommonNamesBatch(
      pendingTaxonomyCommonNames,
    );
    if (onDiagnostics != null) {
      final failedSpeciesIds = <String>{};
      for (final entityKey in failedEntityKeys) {
        failedSpeciesIds.addAll(
          taxonomySpeciesMembership[entityKey] ?? const {},
        );
      }
      onDiagnostics(
        TaxonomyCommonNameDiagnostics(
          failedEntityKeys: failedEntityKeys,
          speciesIdsWithRemainingErrors: failedSpeciesIds,
        ),
      );
    }

    return ImportEnrichmentSummary(
      imageSpeciesCount: 0,
      imageCount: 0,
      commonNameSpeciesCount: enrichedEntityCount,
      commonNameCount: commonNameCount,
    );
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  Future<void> _persistResolvedTaxonId(
    Species species, {
    required int? previousTaxonId,
    required int resolvedTaxonId,
  }) async {
    if (previousTaxonId != null) return;

    await _externalIdCacheRepository.saveExternalId(
      species.id,
      'inaturalist',
      resolvedTaxonId.toString(),
    );
    _log.debug(
      'Stored runtime-resolved iNat external ID for '
      '${species.getBinomialName()} (${species.id}): $resolvedTaxonId',
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
    final result = await _fetchPhotosWithScientificNameFallback(
      species,
      taxonId: taxonId,
      maxPhotos: maxPhotos,
      allowTier3Fallback: allowTier3Fallback,
    );
    if (result == null) {
      return const _SpeciesPhotoFetchOutcome(pictures: [], isTerminal: false);
    }

    await _persistResolvedTaxonId(
      species,
      previousTaxonId: taxonId,
      resolvedTaxonId: result.taxonId,
    );
    await _iNatCacheRepository.cachePhotos(species.id, result.photos);
    return _SpeciesPhotoFetchOutcome(
      pictures: _photoPictureMapper.map(species.id, result.photos),
      isTerminal: true,
    );
  }

  /// Batch-reads known iNat taxon IDs for [speciesList] in two queries:
  /// one against the reference DB and one against the user cache for misses.
  /// Reference-DB entries take precedence over cached ones.
  Future<Map<String, int>> _batchResolveKnownTaxonIds(
    List<Species> speciesList,
  ) async {
    if (speciesList.isEmpty) return const {};
    final ids = speciesList.map((s) => s.id).toSet();
    final refIds = await _externalIdRepository.getExternalIdsForProvider(
      ids,
      'inaturalist',
    );
    final missIds = ids.difference(refIds.keys.toSet());
    final cacheIds = missIds.isEmpty
        ? const <String, int>{}
        : await _externalIdCacheRepository.getExternalIdsForProvider(
            missIds,
            'inaturalist',
          );
    return {...cacheIds, ...refIds};
  }

  Future<({List<Species> candidates, Set<String> terminalSpeciesIds})>
  _buildPrimaryINatPhotoQueue(
    List<Species> speciesList, {
    required bool force,
    required bool prioritizeSpeciesWithoutImages,
  }) async {
    final candidates = <({Species species, int priority})>[];
    final terminalSpeciesIds = <String>{};

    for (final species in speciesList) {
      if (!force) {
        final cachedPhotos = await _iNatCacheRepository.getCachedPhotos(
          species.id,
        );
        if (cachedPhotos != null) {
          terminalSpeciesIds.add(species.id);
          continue;
        }
      }

      final hasReferencePictures = _picturesByUrl(species.pictures).isNotEmpty;
      final priority = prioritizeSpeciesWithoutImages && !hasReferencePictures
          ? 0
          : 1;
      candidates.add((species: species, priority: priority));
    }

    candidates.sort((a, b) {
      final priorityComparison = a.priority.compareTo(b.priority);
      if (priorityComparison != 0) return priorityComparison;
      return a.species.getBinomialName().compareTo(b.species.getBinomialName());
    });

    return (
      candidates: candidates.map((entry) => entry.species).toList(),
      terminalSpeciesIds: terminalSpeciesIds,
    );
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
      if (cachedPhotos == null) {
        continue;
      }
      if (cachedPhotos.isEmpty || cachedPhotos.length >= targetPhotoCount) {
        terminalSpeciesIds.add(species.id);
        continue;
      }

      candidates.add((species: species, cachedPhotoCount: cachedPhotos.length));
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

  /// Returns whether the species reached a terminal common-name outcome.
  ///
  /// Unlike photos, runtime common names historically had no empty marker.
  /// We now persist one through [RuntimeCommonNameRepository.markNoCommonNames]
  /// so the queue can tell "looked up and empty" apart from "not processed".
  Future<_SpeciesCommonNameFetchOutcome> _fetchSpeciesCommonNames(
    Species species, {
    int? taxonId,
  }) async {
    final result = await _fetchCommonNamesWithScientificNameFallback(
      species,
      taxonId: taxonId,
    );
    if (result == null) {
      return const _SpeciesCommonNameFetchOutcome(
        commonNames: {},
        isTerminal: false,
      );
    }

    await _persistResolvedTaxonId(
      species,
      previousTaxonId: taxonId,
      resolvedTaxonId: result.taxonId,
    );
    if (result.commonNames.isEmpty) {
      await _runtimeCommonNameRepository.markNoCommonNames(
        entityKey: _speciesEntityKey(species.id),
        entityType: 'species',
      );
      return const _SpeciesCommonNameFetchOutcome(
        commonNames: {},
        isTerminal: true,
      );
    }
    return _SpeciesCommonNameFetchOutcome(
      commonNames: result.commonNames,
      isTerminal: true,
    );
  }

  Future<({int taxonId, List<INatPhoto> photos})?>
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

    for (final candidate in await _scientificNameCandidates(species)) {
      final result = await _iNatService.fetchPhotos(
        candidate,
        maxPhotos: maxPhotos,
        allowTier3Fallback: allowTier3Fallback,
      );
      if (result == null) continue;
      if (candidate != species.getBinomialName()) {
        _log.debug(
          'iNat photo fallback matched ${species.id}: '
          '${species.getBinomialName()} -> $candidate '
          '(taxon=${result.taxonId})',
        );
      }
      return result;
    }

    return null;
  }

  Future<({int taxonId, Map<String, List<INatCommonName>> commonNames})?>
  _fetchCommonNamesWithScientificNameFallback(
    Species species, {
    required int? taxonId,
  }) async {
    if (taxonId != null) {
      return _iNatService.fetchCommonNames(
        species.getBinomialName(),
        taxonId: taxonId,
      );
    }

    for (final candidate in await _scientificNameCandidates(species)) {
      final result = await _iNatService.fetchCommonNames(candidate);
      if (result == null) continue;
      if (candidate != species.getBinomialName()) {
        _log.debug(
          'iNat common-name fallback matched ${species.id}: '
          '${species.getBinomialName()} -> $candidate '
          '(taxon=${result.taxonId})',
        );
      }
      return result;
    }

    return null;
  }

  Future<List<String>> _scientificNameCandidates(Species species) async {
    final candidates = await _speciesRepository.getScientificNameCandidates(
      species.id,
      preferredScientificName: species.getBinomialName(),
    );
    if (candidates.isNotEmpty) {
      return candidates;
    }
    return [species.getBinomialName()];
  }

  Future<Map<String, List<INatCommonName>>> _fetchTaxonomyCommonNames({
    required String entityKey,
    required String scientificName,
    required String rank,
  }) async {
    final referenceId = await _externalIdRepository.getExternalId(
      entityKey,
      'inaturalist',
    );
    var taxonId = referenceId != null ? int.tryParse(referenceId) : null;
    if (taxonId == null) {
      final savedId = await _externalIdCacheRepository.getExternalId(
        entityKey,
        'inaturalist',
      );
      taxonId = savedId != null ? int.tryParse(savedId) : null;
    }

    final result = await _iNatService.fetchCommonNames(
      scientificName,
      taxonId: taxonId,
      rank: rank,
    );
    if (result == null || result.commonNames.isEmpty) return const {};

    if (taxonId == null) {
      await _externalIdCacheRepository.saveExternalId(
        entityKey,
        'inaturalist',
        result.taxonId.toString(),
      );
    }

    return result.commonNames;
  }

  Map<String, ({String rank, String scientificName})> _buildTaxonomyTargets(
    List<Species> speciesList,
  ) {
    final taxonomyTargets = <String, ({String rank, String scientificName})>{};

    for (final species in speciesList) {
      final classification = species.classification;
      _registerTaxonomyTarget(
        taxonomyTargets,
        rank: 'genus',
        scientificName: classification.genusScientificName,
      );
      _registerTaxonomyTarget(
        taxonomyTargets,
        rank: 'family',
        scientificName: classification.familyScientificName,
      );
      _registerTaxonomyTarget(
        taxonomyTargets,
        rank: 'order',
        scientificName: classification.orderScientificName,
      );
      _registerTaxonomyTarget(
        taxonomyTargets,
        rank: 'class',
        scientificName: classification.classScientificName,
      );
    }

    return taxonomyTargets;
  }

  Map<String, Set<String>> _buildTaxonomySpeciesMembership(
    List<Species> speciesList,
  ) {
    final membership = <String, Set<String>>{};

    for (final species in speciesList) {
      final classification = species.classification;
      void addMember(String rank, String scientificName) {
        membership
            .putIfAbsent(
              _taxonomyEntityKey(rank, scientificName),
              () => <String>{},
            )
            .add(species.id);
      }

      addMember('genus', classification.genusScientificName);
      addMember('family', classification.familyScientificName);
      addMember('order', classification.orderScientificName);
      addMember('class', classification.classScientificName);
    }

    return membership;
  }

  List<String> _sortedTaxonomyEntityKeysForSpecies(List<Species> speciesList) {
    final taxonomySpeciesMembership = _buildTaxonomySpeciesMembership(
      speciesList,
    );
    final entityKeys = taxonomySpeciesMembership.keys.toList(growable: false);
    entityKeys.sort((left, right) {
      final leftCount = taxonomySpeciesMembership[left]?.length ?? 0;
      final rightCount = taxonomySpeciesMembership[right]?.length ?? 0;
      final countComparison = rightCount.compareTo(leftCount);
      if (countComparison != 0) {
        return countComparison;
      }
      return left.compareTo(right);
    });
    return entityKeys;
  }

  void _registerTaxonomyTarget(
    Map<String, ({String rank, String scientificName})> taxonomyTargets, {
    required String rank,
    required String scientificName,
  }) {
    taxonomyTargets[_taxonomyEntityKey(rank, scientificName)] = (
      rank: rank,
      scientificName: scientificName,
    );
  }

  Map<Language, List<String>> _referenceCommonNamesForTaxonomyTarget(
    List<Species> speciesList,
    String rank,
    String scientificName,
  ) {
    for (final species in speciesList) {
      final classification = species.classification;
      switch (rank) {
        case 'genus':
          if (classification.genusScientificName == scientificName) {
            return classification.genusCommonNames;
          }
          break;
        case 'family':
          if (classification.familyScientificName == scientificName) {
            return classification.familyCommonNames;
          }
          break;
        case 'order':
          if (classification.orderScientificName == scientificName) {
            return classification.orderCommonNames;
          }
          break;
        case 'class':
          if (classification.classScientificName == scientificName) {
            return classification.classCommonNames;
          }
          break;
      }
    }

    return const {};
  }

  String _entityTypeForTaxonomyRank(String rank) {
    switch (rank) {
      case 'genus':
        return 'genera';
      case 'family':
        return 'families';
      case 'order':
        return 'orders';
      case 'class':
        return 'classes';
      default:
        return rank;
    }
  }

  String _taxonomyEntityKey(String rank, String scientificName) {
    return '$rank:${scientificName.trim().toLowerCase()}';
  }

  Future<String> _taxonomyWorkKey({
    required String runtimeEntityKey,
    required String rank,
  }) async {
    final referenceId = await _externalIdRepository.getExternalId(
      runtimeEntityKey,
      'inaturalist',
    );
    var taxonId = referenceId != null ? int.tryParse(referenceId) : null;
    if (taxonId == null) {
      final savedId = await _externalIdCacheRepository.getExternalId(
        runtimeEntityKey,
        'inaturalist',
      );
      taxonId = savedId != null ? int.tryParse(savedId) : null;
    }
    if (taxonId != null) {
      return '$rank:taxon:$taxonId';
    }
    return runtimeEntityKey;
  }

  String _speciesEntityKey(String speciesId) {
    return 'species:$speciesId';
  }

  List<String> _orderedUniqueStrings(Iterable<String> values) {
    final ordered = <String>[];
    final seen = <String>{};
    for (final value in values) {
      final normalized = value.trim();
      if (normalized.isEmpty || !seen.add(normalized)) {
        continue;
      }
      ordered.add(normalized);
    }
    return ordered;
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

class _SpeciesCommonNameFetchOutcome {
  final Map<String, List<INatCommonName>> commonNames;
  final bool isTerminal;

  const _SpeciesCommonNameFetchOutcome({
    required this.commonNames,
    required this.isTerminal,
  });
}
