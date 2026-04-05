import 'package:flutter/foundation.dart';

import '../../external/inaturalist/inaturalist_service.dart';
import '../../model/biology/picture.dart';
import '../../model/learning/base_deck.dart';
import '../../model/learning/deck_stat.dart';
import '../../model/learning/flash_card_stat.dart';
import '../../model/ui/create_deck.dart';
import '../../model/ui/view_deck.dart';
import '../../persistence/deck_repository.dart';
import '../../persistence/flash_card_stat_repository.dart';
import '../../persistence/external_id_repository.dart';
import '../../persistence/external_id_cache_repository.dart';
import '../../persistence/inat_common_name_repository.dart';
import '../../persistence/inat_photo_cache_repository.dart';
import '../../persistence/inat_taxonomy_common_name_repository.dart';
import '../../persistence/species_repository.dart';
import '../common/image_service.dart';
import '../../model/biology/species.dart';

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

/// Application service for deck lifecycle operations and import enrichment.
///
/// Besides creating, updating, and deleting decks, this service coordinates the
/// post-import enrichment pipeline that augments deck species with cached
/// images and multilingual common names from iNaturalist.
class DecksService extends ChangeNotifier {
  static const _maxConcurrentINatSpeciesFetches = 3;

  final DeckRepository _deckRepository;
  final SpeciesRepository _speciesRepository;
  final FlashCardStatRepository _flashCardStatRepository;
  final ImageService _imageService;
  final INaturalistService _iNatService;
  final INatPhotoCacheRepository _iNatCacheRepository;
  final INatCommonNameRepository _iNatCommonNameRepository;
  final INatTaxonomyCommonNameRepository _iNatTaxonomyCommonNameRepository;
  final ExternalIdRepository _externalIdRepository;
  final ExternalIdCacheRepository _externalIdCacheRepository;

  DecksService(
    this._deckRepository,
    this._flashCardStatRepository,
    this._speciesRepository,
    this._imageService,
    this._iNatService,
    this._iNatCacheRepository,
    this._externalIdRepository,
    this._externalIdCacheRepository, {
    INatCommonNameRepository? iNatCommonNameRepository,
    INatTaxonomyCommonNameRepository? iNatTaxonomyCommonNameRepository,
  }) : _iNatCommonNameRepository =
           iNatCommonNameRepository ?? INatCommonNameRepository(),
       _iNatTaxonomyCommonNameRepository =
           iNatTaxonomyCommonNameRepository ??
           INatTaxonomyCommonNameRepository();

  Future<String> createDeck(CreateDeck deck) async {
    final id = await _deckRepository.insertDeck(deck);
    // Ensure the deck object has the ID for initialization
    final updatedDeck = CreateDeck(
      id: id,
      name: deck.name,
      description: deck.description,
      language: deck.language,
      speciesIds: deck.speciesIds,
    )..coverImagePath = deck.coverImagePath;

    await _initializeDeck(updatedDeck);
    notifyListeners();
    return id;
  }

  Future<void> updateDeck(
    BaseDeck updatedDeck,
    Set<String> newSpeciesIds,
  ) async {
    // 1. Upsert deck metadata (insertDeck uses conflictAlgorithm: replace)
    await _deckRepository.insertDeck(updatedDeck);

    // 2. Diff species list
    final currentIds = await _flashCardStatRepository.getSpeciesIdsByDeckId(
      updatedDeck.id!,
    );
    final removed = currentIds.difference(newSpeciesIds);
    final added = newSpeciesIds.difference(currentIds);

    // 3. Remove flash-card stats for removed species
    if (removed.isNotEmpty) {
      await _flashCardStatRepository.deleteFlashCardStats(
        updatedDeck.id!,
        removed,
      );
    }

    // 4. Insert flash-card stats for newly added species (preserves progress for existing)
    if (added.isNotEmpty) {
      final newStats = added
          .map(
            (speciesId) =>
                FlashCardStat(speciesId: speciesId, deckId: updatedDeck.id!),
          )
          .toSet();
      await _flashCardStatRepository.insertOrUpdateFlashCardStats(newStats);
    }

    notifyListeners();
  }

  Future<void> _initializeDeck(CreateDeck deck) async {
    final speciesIds = deck.speciesIds ?? {};
    if (speciesIds.isEmpty) return;

    final Set<FlashCardStat> flashCardStats = speciesIds
        .map(
          (speciesId) => FlashCardStat(speciesId: speciesId, deckId: deck.id!),
        )
        .toSet();

    await _flashCardStatRepository.insertOrUpdateFlashCardStats(flashCardStats);
  }

  Future<List<ViewDeck>> getAllDecks() async {
    final List<BaseDeck> decks = await _deckRepository.getAllDecks();
    return await _createViewDecks(decks);
  }

  Future<List<ViewDeck>> getDecks(Set<String> deckIds) async {
    final List<BaseDeck> decks = await _getRawDecksByIds(deckIds);
    return await _createViewDecks(decks);
  }

  Future<CreateDeck> getCreateDeck(String deckId) async {
    final List<BaseDeck> decks = await _getRawDecksByIds({deckId});
    if (decks.isEmpty) {
      throw Exception('Deck not found: $deckId');
    }
    final deck = decks.first;
    final speciesList = await getSpeciesByDeckId(deckId);
    final speciesNames = speciesList.map((s) => s.getBinomialName()).toSet();
    final speciesIds = speciesList.map((s) => s.id).toSet();

    return CreateDeck(
      id: deck.id,
      name: deck.name,
      description: deck.description,
      language: deck.language,
      speciesNames: speciesNames,
      speciesIds: speciesIds,
    )..coverImagePath = deck.coverImagePath;
  }

  Future<List<Species>> getSpeciesByDeckId(String deckId) async {
    final speciesIds = await _flashCardStatRepository.getSpeciesIdsByDeckId(
      deckId,
    );
    if (speciesIds.isEmpty) return [];

    final speciesSet = await _speciesRepository.getSpecies(speciesIds);
    return speciesSet.toList();
  }

  Future<List<Species>> getSpeciesByIds(Set<String> ids) async {
    if (ids.isEmpty) return [];
    final speciesSet = await _speciesRepository.getSpecies(ids);
    return speciesSet.toList();
  }

  Future<List<BaseDeck>> _getRawDecksByIds(Set<String> deckIds) async {
    return _deckRepository.getDecksByIds(deckIds);
  }

  Future<void> deleteDeck(String deckId) async {
    await _deleteDeckCoverImage(deckId);
    await _deckRepository.delete(deckId);
    notifyListeners();
  }

  Future<List<ViewDeck>> _createViewDecks(List<BaseDeck> decks) async {
    final List<ViewDeck> viewDecks = [];
    for (BaseDeck deck in decks) {
      DeckStat deckStat = await _flashCardStatRepository.getDeckStat(deck.id!);

      double progress = deckStat.uninitializedCount == 0
          ? 1
          : 1 - (deckStat.uninitializedCount / deckStat.totalCount);
      viewDecks.add(ViewDeck.fromBase(deck, progress));
    }
    return viewDecks;
  }

  /// Downloads all reference images (FishBase/SLB) for a list of decks that aren't already local.
  Future<ImportEnrichmentSummary> downloadBaseImagesForDecks(
    List<String> deckIds, {
    void Function(int completed, int total)? onProgress,
  }) async {
    final allSpeciesIds = await _getSpeciesIdsForDecks(deckIds);
    if (allSpeciesIds.isEmpty) {
      onProgress?.call(0, 0);
      return ImportEnrichmentSummary.empty;
    }

    final speciesSet = await _speciesRepository.getSpecies(allSpeciesIds);
    final speciesList = speciesSet.toList();
    final total = speciesList.length;
    var completed = 0;
    var speciesWithImages = 0;
    var imageCount = 0;

    onProgress?.call(0, total);

    await _runWithConcurrency<Species>(
      speciesList,
      maxConcurrent: _maxConcurrentINatSpeciesFetches,
      task: (species) async {
        try {
          final picturesByUrl = _picturesByUrl(species.pictures);
          if (picturesByUrl.isNotEmpty) {
            await _imageService.downloadAndSavePicturesMap(species.pictures);
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
  ///
  /// This path intentionally downloads the resolved iNat image files directly so
  /// the dialog can show real progress for external images.
  /// Returns a summary of how many species and images were downloaded.
  Future<ImportEnrichmentSummary> fetchINatPhotosForDecks(
    List<String> deckIds, {
    void Function(int completed, int total)? onProgress,
    bool force = false,
  }) async {
    final allSpeciesIds = await _getSpeciesIdsForDecks(deckIds);
    if (allSpeciesIds.isEmpty) {
      onProgress?.call(0, 0);
      return ImportEnrichmentSummary.empty;
    }

    final speciesList = (await _speciesRepository.getSpecies(
      allSpeciesIds,
    )).toList();
    final total = speciesList.length;
    var completed = 0;
    var enrichedCount = 0;
    var imageCount = 0;

    onProgress?.call(0, total);

    await _runWithConcurrency<Species>(
      speciesList,
      maxConcurrent: _maxConcurrentINatSpeciesFetches,
      task: (species) async {
        try {
          final pictures = await _fetchAndPersistINatPictures(species);

          if (pictures.isNotEmpty) {
            enrichedCount++;
            imageCount += _picturesByUrl(pictures).length;
            await _imageService.downloadAndSavePicturesMap(pictures);
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

  Future<ImportEnrichmentSummary> fetchINatCommonNamesForDecks(
    List<String> deckIds, {
    void Function(int completed, int total)? onProgress,
    bool force = false,
  }) async {
    final allSpeciesIds = await _getSpeciesIdsForDecks(deckIds);
    if (allSpeciesIds.isEmpty) {
      onProgress?.call(0, 0);
      return ImportEnrichmentSummary.empty;
    }

    final speciesList = (await _speciesRepository.getSpecies(
      allSpeciesIds,
    )).toList();
    final persistedNamesBySpecies = await _iNatCommonNameRepository
        .getCommonNamesForSpecies(allSpeciesIds);
    final total = speciesList.length;
    var completed = 0;
    var enrichedSpeciesCount = 0;
    var commonNameCount = 0;

    onProgress?.call(0, total);

    await _runWithConcurrency<Species>(
      speciesList,
      maxConcurrent: _maxConcurrentINatSpeciesFetches,
      task: (species) async {
        try {
          final persistedNames =
              persistedNamesBySpecies[species.id] ?? const {};
          if (!force && _hasSupportedCommonNames(persistedNames)) {
            return;
          }

          final serializedNames = await _fetchSerializedSpeciesCommonNames(
            species,
          );
          if (serializedNames.isEmpty) {
            return;
          }

          await _iNatCommonNameRepository.saveCommonNames(
            species.id,
            serializedNames,
          );
          enrichedSpeciesCount++;
          commonNameCount += serializedNames.length;
        } catch (e) {
          debugPrint('iNat common-name fetch failed for ${species.id}: $e');
        } finally {
          completed++;
          onProgress?.call(completed, total);
        }
      },
    );

    final taxonomySummary = await fetchINatTaxonomyCommonNamesForDecks(
      deckIds,
      force: force,
    );

    return ImportEnrichmentSummary(
      imageSpeciesCount: 0,
      imageCount: 0,
      commonNameSpeciesCount:
          enrichedSpeciesCount + taxonomySummary.commonNameSpeciesCount,
      commonNameCount: commonNameCount + taxonomySummary.commonNameCount,
    );
  }

  Future<ImportEnrichmentSummary> fetchINatTaxonomyCommonNamesForDecks(
    List<String> deckIds, {
    bool force = false,
  }) async {
    final allSpeciesIds = await _getSpeciesIdsForDecks(deckIds);
    if (allSpeciesIds.isEmpty) {
      return ImportEnrichmentSummary.empty;
    }

    final speciesList = (await _speciesRepository.getSpecies(
      allSpeciesIds,
    )).toList();
    final taxonomyTargets = _buildTaxonomyTargets(speciesList);

    final existingCommonNames = await _iNatTaxonomyCommonNameRepository
        .getCommonNamesForEntities(taxonomyTargets.keys.toSet());

    var enrichedEntityCount = 0;
    var commonNameCount = 0;

    await _runWithConcurrency<String>(
      taxonomyTargets.keys.toList(),
      maxConcurrent: _maxConcurrentINatSpeciesFetches,
      task: (entityKey) async {
        final taxonomyTarget = taxonomyTargets[entityKey]!;
        final existing = existingCommonNames[entityKey] ?? const {};
        if (!force && _hasSupportedCommonNames(existing)) {
          return;
        }

        try {
          final serializedNames = await _fetchSerializedTaxonomyCommonNames(
            scientificName: taxonomyTarget.scientificName,
            rank: taxonomyTarget.rank,
          );
          if (serializedNames.isEmpty) return;

          await _iNatTaxonomyCommonNameRepository.saveCommonNames(
            entityKey,
            serializedNames,
          );
          enrichedEntityCount++;
          commonNameCount += serializedNames.length;
        } catch (e) {
          debugPrint(
            'iNat taxonomy common-name fetch failed for $entityKey: $e',
          );
        }
      },
    );

    return ImportEnrichmentSummary(
      imageSpeciesCount: 0,
      imageCount: 0,
      commonNameSpeciesCount: enrichedEntityCount,
      commonNameCount: commonNameCount,
    );
  }

  Future<Set<String>> _getSpeciesIdsForDecks(List<String> deckIds) async {
    final speciesIdsByDeck = <String>{};
    for (final deckId in deckIds) {
      speciesIdsByDeck.addAll(
        await _flashCardStatRepository.getSpeciesIdsByDeckId(deckId),
      );
    }
    return speciesIdsByDeck;
  }

  Future<void> _deleteDeckCoverImage(String deckId) async {
    final decks = await _deckRepository.getDecksByIds({deckId});
    if (decks.isEmpty) return;

    final coverImagePath = decks.first.coverImagePath;
    if (coverImagePath == null || coverImagePath.isEmpty) return;
    await _imageService.deleteImage(coverImagePath);
  }

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

  Future<List<Picture>> _fetchAndPersistINatPictures(Species species) async {
    final taxonId = await _resolveINatTaxonId(species);
    final result = await _iNatService.fetchPhotos(
      species.getBinomialName(),
      taxonId: taxonId,
    );
    if (result == null) return const [];

    await _persistResolvedTaxonId(
      species,
      previousTaxonId: taxonId,
      resolvedTaxonId: result.taxonId,
    );
    await _iNatCacheRepository.cachePhotos(species.id, result.photos);
    return _mapINatPhotosToPictures(species.id, result.photos);
  }

  Future<Map<String, String>> _fetchSerializedSpeciesCommonNames(
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
    return _serializeCommonNamesByLanguage(result.commonNames);
  }

  Future<Map<String, String>> _fetchSerializedTaxonomyCommonNames({
    required String scientificName,
    required String rank,
  }) async {
    final result = await _iNatService.fetchCommonNames(
      scientificName,
      rank: rank,
    );
    if (result == null || result.commonNames.isEmpty) return const {};
    return _serializeCommonNamesByLanguage(result.commonNames);
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

  bool _hasSupportedCommonNames(Map<String, String> commonNames) {
    const supportedLanguages = {'de', 'en', 'fr', 'es'};
    for (final code in supportedLanguages) {
      final names = commonNames[code];
      if (names != null && names.trim().isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  String _serializeNames(List<String> names) {
    final uniqueNames = <String>[];
    final seen = <String>{};

    for (final name in names) {
      final trimmed = name.trim();
      final normalized = trimmed.replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
      if (normalized.isEmpty || seen.contains(normalized)) continue;
      seen.add(normalized);
      uniqueNames.add(trimmed);
    }

    return uniqueNames.join(';');
  }

  Map<String, String> _serializeCommonNamesByLanguage(
    Map<String, List<String>> commonNamesByLanguage,
  ) {
    final serializedNames = <String, String>{};
    for (final entry in commonNamesByLanguage.entries) {
      final serializedNamesForLanguage = _serializeNames(entry.value);
      if (serializedNamesForLanguage.isEmpty) continue;
      serializedNames[entry.key] = serializedNamesForLanguage;
    }
    return serializedNames;
  }

  List<Picture> _mapINatPhotosToPictures(
    String speciesId,
    List<dynamic> photos,
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

  String _taxonomyEntityKey(String rank, String scientificName) {
    return '$rank:${scientificName.trim().toLowerCase()}';
  }

  Future<void> _runWithConcurrency<T>(
    List<T> items, {
    required int maxConcurrent,
    required Future<void> Function(T item) task,
  }) async {
    if (items.isEmpty) return;

    var nextIndex = 0;

    Future<void> worker() async {
      while (true) {
        final currentIndex = nextIndex;
        if (currentIndex >= items.length) return;
        nextIndex++;
        await task(items[currentIndex]);
      }
    }

    final workerCount = items.length < maxConcurrent
        ? items.length
        : maxConcurrent;
    await Future.wait(List.generate(workerCount, (_) => worker()));
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
