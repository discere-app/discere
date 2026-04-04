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
import '../../persistence/inat_photo_cache_repository.dart';
import '../../persistence/species_repository.dart';
import '../common/image_service.dart';
import '../../model/biology/species.dart';

class ImageDownloadSummary {
  final int speciesCount;
  final int imageCount;

  const ImageDownloadSummary({
    required this.speciesCount,
    required this.imageCount,
  });

  static const empty = ImageDownloadSummary(speciesCount: 0, imageCount: 0);

  ImageDownloadSummary operator +(ImageDownloadSummary other) {
    return ImageDownloadSummary(
      speciesCount: speciesCount + other.speciesCount,
      imageCount: imageCount + other.imageCount,
    );
  }
}

class DecksService extends ChangeNotifier {
  static const _maxConcurrentINatSpeciesFetches = 3;

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
  Future<ImageDownloadSummary> downloadBaseImagesForDecks(
    List<String> deckIds, {
    void Function(int completed, int total)? onProgress,
  }) async {
    final Set<String> allSpeciesIds = {};
    for (final deckId in deckIds) {
      allSpeciesIds.addAll(
        await _flashCardStatRepository.getSpeciesIdsByDeckId(deckId),
      );
    }
    if (allSpeciesIds.isEmpty) {
      onProgress?.call(0, 0);
      return ImageDownloadSummary.empty;
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

    return ImageDownloadSummary(
      speciesCount: speciesWithImages,
      imageCount: imageCount,
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
  Future<ImageDownloadSummary> fetchINatPhotosForDecks(
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
    if (allSpeciesIds.isEmpty) {
      onProgress?.call(0, 0);
      return ImageDownloadSummary.empty;
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
            return;
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

          final pictures = result.photos
              .map(
                (photo) => Picture(
                  id: 'inat_${species.id}_${photo.mediumUrl.hashCode}',
                  species: species.id,
                  url: photo.mediumUrl,
                  author: photo.attribution,
                  origin: 'iNaturalist',
                  licenseKey: (photo.licenseCode ?? '').toUpperCase(),
                  isUsable: 1,
                ),
              )
              .toList();

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

    return ImageDownloadSummary(
      speciesCount: enrichedCount,
      imageCount: imageCount,
    );
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
