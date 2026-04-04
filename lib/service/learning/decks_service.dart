import 'package:flutter/material.dart';

import '../../external/inaturalist/inaturalist_service.dart';
import '../../model/learning/base_deck.dart';
import '../../model/learning/deck_stat.dart';
import '../../model/learning/flash_card_stat.dart';
import '../../model/ui/create_deck.dart';
import '../../model/ui/view_deck.dart';
import '../../persistence/deck_repository.dart';
import '../../persistence/flash_card_stat_repository.dart';
import '../../persistence/external_id_repository.dart';
import '../../persistence/external_id_cache_repository.dart';
import '../../persistence/inat_photo_cache_repository.dart';
import '../../persistence/species_repository.dart';
import '../common/image_service.dart';
import '../../model/biology/species.dart';

class DecksService extends ChangeNotifier {
  final DeckRepository _deckRepository;
  final SpeciesRepository _speciesRepository;
  final FlashCardStatRepository _flashCardStatRepository;
  final ImageService _imageService;
  final INaturalistService _iNatService;
  final INatPhotoCacheRepository _iNatCacheRepository;
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
    this._externalIdCacheRepository,
  );

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
    // 1. Get the deck to find the cover image path
    final decks = await _deckRepository.getDecksByIds({deckId});
    if (decks.isNotEmpty) {
      final coverPath = decks.first.coverImagePath;
      if (coverPath != null && coverPath.isNotEmpty) {
        await _imageService.deleteImage(coverPath);
      }
    }

    // 2. Delete from database
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
  Future<void> downloadBaseImagesForDecks(List<String> deckIds) async {
    final Set<String> allSpeciesIds = {};
    for (final deckId in deckIds) {
      allSpeciesIds.addAll(
        await _flashCardStatRepository.getSpeciesIdsByDeckId(deckId),
      );
    }
    if (allSpeciesIds.isEmpty) return;

    final speciesSet = await _speciesRepository.getSpecies(allSpeciesIds);
    final urls = speciesSet
        .expand((s) => s.pictures)
        .map((p) => p.url)
        .where((url) => url != null && url.isNotEmpty)
        .cast<String>()
        .toSet();

    if (urls.isNotEmpty) {
      await _imageService
          .downloadAndSaveImagesMap(urls)
          .catchError((e) => <String, String>{});
    }
  }

  /// Fetches iNaturalist photos for all species in the given decks.
  ///
  /// Call this after deck creation/import, with user consent.
  /// [onProgress] is called with (completed, total) for UI progress display.
  /// If [force] is true, re-fetches even if previously cached.
  /// Returns the number of species that received new photos.
  Future<int> fetchINatPhotosForDecks(
    List<String> deckIds, {
    void Function(int completed, int total)? onProgress,
    bool force = false,
  }) async {
    final Set<String> allSpeciesIds = {};
    for (final deckId in deckIds) {
      allSpeciesIds.addAll(
        await _flashCardStatRepository.getSpeciesIdsByDeckId(deckId),
      );
    }
    if (allSpeciesIds.isEmpty) return 0;

    final speciesSet = await _speciesRepository.getSpecies(allSpeciesIds);
    final total = speciesSet.length;
    var completed = 0;
    var enrichedCount = 0;

    for (final species in speciesSet) {
      try {
        final cached = await _iNatCacheRepository.getCachedPhotos(species.id);

        // Skip only if:
        // 1. We aren't forcing a refresh.
        // 2. We already have a result.
        // 3. That result is NOT empty (unless the empty result is very recent).
        if (!force && cached != null && cached.isNotEmpty) {
          completed++;
          onProgress?.call(completed, total);
          continue;
        }

        // 1. Try reference DB (ETL-resolved), then user DB (runtime-resolved)
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

        if (taxonId == null) {
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
        }

        // 2. Fetch from iNat API (Smart Resolution inside the service)
        final result = await _iNatService.fetchPhotos(
          species.getBinomialName(),
          taxonId: taxonId,
        );

        if (result == null) {
          completed++;
          onProgress?.call(completed, total);
          continue;
        }

        // 3. Save the resolved ID if it's new
        if (taxonId == null) {
          await _externalIdCacheRepository.saveExternalId(
            species.id,
            'inaturalist',
            result.taxonId.toString(),
          );
          if (kDebugMode) {
            debugPrint(
              'Stored runtime-resolved iNat external ID for '
              '${species.getBinomialName()} (${species.id}): ${result.taxonId}',
            );
          }
        }

        await _iNatCacheRepository.cachePhotos(species.id, result.photos);

        if (result.photos.isNotEmpty) enrichedCount++;
      } catch (e) {
        debugPrint('iNat fetch failed for ${species.id}: $e');
      }

      completed++;
      onProgress?.call(completed, total);
    }

    return enrichedCount;
  }
}
