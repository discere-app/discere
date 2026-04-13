import 'package:flutter/foundation.dart';

import 'package:discere/enrichment/mapper/inaturalist_photo_picture_mapper.dart';
import 'package:discere/shared/external/inaturalist_service.dart';
import 'package:discere/shared/external/models/inat_common_name.dart';
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

/// Coordinates post-import enrichment of deck species with iNaturalist
/// photos and multilingual common names.
class EnrichmentService {
  static const _maxConcurrentINatSpeciesFetches = 3;
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
  /// [onProgress] is called with (completed, total) for image download progress.
  /// Returns a summary of how many species and images were downloaded.
  Future<ImportEnrichmentSummary> fetchINatPhotosForSpecies(
    Set<String> speciesIds, {
    void Function(int completed, int total)? onProgress,
    bool force = false,
    bool primaryOnly = false,
    bool prioritizeSpeciesWithoutImages = false,
    int maxConcurrent = _maxConcurrentINatSpeciesFetches,
    Duration? requestSpacing,
  }) async {
    if (speciesIds.isEmpty) {
      onProgress?.call(0, 0);
      return ImportEnrichmentSummary.empty;
    }

    final speciesList = (await _speciesRepository.getSpecies(
      speciesIds,
    )).toList();
    final candidates = await _buildPrimaryINatPhotoQueue(
      speciesList,
      force: force,
      prioritizeSpeciesWithoutImages: prioritizeSpeciesWithoutImages,
    );
    final total = candidates.length;
    var completed = 0;
    var enrichedCount = 0;
    var imageCount = 0;

    if (candidates.isEmpty) {
      onProgress?.call(0, 0);
      return ImportEnrichmentSummary.empty;
    }

    onProgress?.call(0, total);

    await runThrottled<Species>(
      candidates,
      maxConcurrent: maxConcurrent,
      requestSpacing: requestSpacing,
      task: (species) async {
        try {
          final pictures = await _fetchAndPersistINatPictures(
            species,
            maxPhotos: primaryOnly ? 1 : 10,
          );

          if (pictures.isNotEmpty) {
            enrichedCount++;
            imageCount += _picturesByUrl(pictures).length;
            await _imageService.downloadAndSaveUrlMap(
              _picturesByUrl(pictures).keys.toSet(),
              storageDirectory: _externalImagesDirectory,
            );
          }
        } catch (e) {
          debugPrint('iNat fetch failed for ${species.id}: $e');
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
    int targetPhotoCount = 10,
    int maxConcurrent = _maxConcurrentINatSpeciesFetches,
    Duration? requestSpacing,
  }) async {
    if (speciesIds.isEmpty) {
      onProgress?.call(0, 0);
      return ImportEnrichmentSummary.empty;
    }

    final speciesList = (await _speciesRepository.getSpecies(
      speciesIds,
    )).toList();
    final candidates = await _buildBackfillINatPhotoQueue(
      speciesList,
      targetPhotoCount: targetPhotoCount,
    );
    final total = candidates.length;
    var completed = 0;
    var enrichedCount = 0;
    var imageCount = 0;

    if (candidates.isEmpty) {
      onProgress?.call(0, 0);
      return ImportEnrichmentSummary.empty;
    }

    onProgress?.call(0, total);

    await runThrottled<Species>(
      candidates,
      maxConcurrent: maxConcurrent,
      requestSpacing: requestSpacing,
      task: (species) async {
        try {
          final pictures = await _fetchAndPersistINatPictures(
            species,
            maxPhotos: targetPhotoCount,
          );

          if (pictures.isNotEmpty) {
            enrichedCount++;
            imageCount += _picturesByUrl(pictures).length;
            await _imageService.downloadAndSaveUrlMap(
              _picturesByUrl(pictures).keys.toSet(),
              storageDirectory: _externalImagesDirectory,
            );
          }
        } catch (e) {
          debugPrint('iNat backfill failed for ${species.id}: $e');
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

  Future<ImportEnrichmentSummary> fetchINatCommonNamesForSpecies(
    Set<String> speciesIds, {
    void Function(int completed, int total)? onProgress,
    bool force = false,
    int maxConcurrent = _maxConcurrentINatSpeciesFetches,
    Duration? requestSpacing,
  }) async {
    if (speciesIds.isEmpty) {
      onProgress?.call(0, 0);
      return ImportEnrichmentSummary.empty;
    }

    final speciesList = (await _speciesRepository.getSpecies(
      speciesIds,
    )).toList();
    final entitiesWithNames = await _runtimeCommonNameRepository
        .getEntitiesWithCommonNames(
          speciesIds.map((speciesId) => _speciesEntityKey(speciesId)).toSet(),
        );
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
      task: (species) async {
        try {
          if (!force &&
              entitiesWithNames.contains(_speciesEntityKey(species.id))) {
            return;
          }

          final commonNames = await _fetchSpeciesCommonNames(species);
          if (commonNames.isEmpty) return;

          pendingSpeciesCommonNames[species] = commonNames;
          enrichedSpeciesCount++;
          commonNameCount +=
              commonNames.values.fold(0, (sum, list) => sum + list.length);
        } catch (e) {
          debugPrint('iNat common-name fetch failed for ${species.id}: $e');
        } finally {
          completed++;
          onProgress?.call(completed, total);
        }
      },
    );

    await _runtimeCommonNameRepository.saveSpeciesCommonNamesBatch(
      pendingSpeciesCommonNames,
    );

    final taxonomySummary = await fetchINatTaxonomyCommonNamesForSpecies(
      speciesIds,
      force: force,
      maxConcurrent: maxConcurrent,
      requestSpacing: requestSpacing,
    );

    return ImportEnrichmentSummary(
      imageSpeciesCount: 0,
      imageCount: 0,
      commonNameSpeciesCount:
          enrichedSpeciesCount + taxonomySummary.commonNameSpeciesCount,
      commonNameCount: commonNameCount + taxonomySummary.commonNameCount,
    );
  }

  Future<ImportEnrichmentSummary> fetchINatTaxonomyCommonNamesForSpecies(
    Set<String> speciesIds, {
    bool force = false,
    int maxConcurrent = _maxConcurrentINatSpeciesFetches,
    Duration? requestSpacing,
  }) async {
    if (speciesIds.isEmpty) {
      return ImportEnrichmentSummary.empty;
    }

    final speciesList = (await _speciesRepository.getSpecies(
      speciesIds,
    )).toList();
    final taxonomyTargets = _buildTaxonomyTargets(speciesList);

    final entitiesWithNames = await _runtimeCommonNameRepository
        .getEntitiesWithCommonNames(taxonomyTargets.keys.toSet());

    var enrichedEntityCount = 0;
    var commonNameCount = 0;
    final pendingTaxonomyCommonNames = <RuntimeTaxonomyCommonNameRecord>[];

    await runThrottled<String>(
      taxonomyTargets.keys.toList(),
      maxConcurrent: maxConcurrent,
      requestSpacing: requestSpacing,
      task: (entityKey) async {
        final taxonomyTarget = taxonomyTargets[entityKey]!;
        if (!force && entitiesWithNames.contains(entityKey)) return;

        try {
          final commonNames = await _fetchTaxonomyCommonNames(
            entityKey: entityKey,
            scientificName: taxonomyTarget.scientificName,
            rank: taxonomyTarget.rank,
          );
          if (commonNames.isEmpty) return;

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
          commonNameCount +=
              commonNames.values.fold(0, (sum, list) => sum + list.length);
        } catch (e) {
          debugPrint(
            'iNat taxonomy common-name fetch failed for $entityKey: $e',
          );
        }
      },
    );

    await _runtimeCommonNameRepository.saveTaxonomyCommonNamesBatch(
      pendingTaxonomyCommonNames,
    );

    return ImportEnrichmentSummary(
      imageSpeciesCount: 0,
      imageCount: 0,
      commonNameSpeciesCount: enrichedEntityCount,
      commonNameCount: commonNameCount,
    );
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  Future<int?> _resolveINatTaxonId(Species species) async {
    final referenceId = await _externalIdRepository.getExternalId(
      species.id,
      'inaturalist',
    );
    int? taxonId = referenceId != null ? int.tryParse(referenceId) : null;
    if (kDebugMode && taxonId != null) {
      debugPrint(
        'iNat external ID from reference DB for ${species.getBinomialName()} '
        '(${species.id}): $taxonId',
      );
    }

    if (taxonId != null) return taxonId;

    final savedId = await _externalIdCacheRepository.getExternalId(
      species.id,
      'inaturalist',
    );
    taxonId = savedId != null ? int.tryParse(savedId) : null;
    if (kDebugMode) {
      if (taxonId != null) {
        debugPrint(
          'iNat external ID from user cache for ${species.getBinomialName()} '
          '(${species.id}): $taxonId',
        );
      } else {
        debugPrint(
          'No iNat external ID found for ${species.getBinomialName()} '
          '(${species.id}) in reference DB or user cache; resolving live.',
        );
      }
    }

    return taxonId;
  }

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
    if (kDebugMode) {
      debugPrint(
        'Stored runtime-resolved iNat external ID for '
        '${species.getBinomialName()} (${species.id}): $resolvedTaxonId',
      );
    }
  }

  Future<List<Picture>> _fetchAndPersistINatPictures(
    Species species, {
    int maxPhotos = 10,
  }) async {
    final taxonId = await _resolveINatTaxonId(species);
    final result = await _iNatService.fetchPhotos(
      species.getBinomialName(),
      taxonId: taxonId,
      maxPhotos: maxPhotos,
    );
    if (result == null) return const [];

    await _persistResolvedTaxonId(
      species,
      previousTaxonId: taxonId,
      resolvedTaxonId: result.taxonId,
    );
    await _iNatCacheRepository.cachePhotos(species.id, result.photos);
    return _photoPictureMapper.map(species.id, result.photos);
  }

  Future<List<Species>> _buildPrimaryINatPhotoQueue(
    List<Species> speciesList, {
    required bool force,
    required bool prioritizeSpeciesWithoutImages,
  }) async {
    final candidates = <({Species species, int priority})>[];

    for (final species in speciesList) {
      if (!force) {
        final cachedPhotos = await _iNatCacheRepository.getCachedPhotos(
          species.id,
        );
        if (cachedPhotos != null) {
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

    return candidates.map((entry) => entry.species).toList();
  }

  Future<List<Species>> _buildBackfillINatPhotoQueue(
    List<Species> speciesList, {
    int targetPhotoCount = 10,
  }) async {
    final candidates = <({Species species, int cachedPhotoCount})>[];

    for (final species in speciesList) {
      final cachedPhotos = await _iNatCacheRepository.getCachedPhotos(
        species.id,
      );
      if (cachedPhotos == null ||
          cachedPhotos.isEmpty ||
          cachedPhotos.length >= targetPhotoCount) {
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

    return candidates.map((entry) => entry.species).toList();
  }

  Future<Map<String, List<INatCommonName>>> _fetchSpeciesCommonNames(
    Species species,
  ) async {
    final taxonId = await _resolveINatTaxonId(species);
    final result = await _iNatService.fetchCommonNames(
      species.getBinomialName(),
      taxonId: taxonId,
    );
    if (result == null || result.commonNames.isEmpty) return const {};

    await _persistResolvedTaxonId(
      species,
      previousTaxonId: taxonId,
      resolvedTaxonId: result.taxonId,
    );
    return result.commonNames;
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

  String _speciesEntityKey(String speciesId) {
    return 'species:$speciesId';
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
