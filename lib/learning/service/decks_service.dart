import 'package:flutter/foundation.dart';

import 'package:discere/catalog/model/species.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/deck_stat.dart';
import 'package:discere/learning/model/flash_card_stat.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/model/view_deck.dart';
import 'package:discere/learning/repository/deck_repository.dart';
import 'package:discere/learning/repository/flash_card_stat_repository.dart';
import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/shared/service/image_service.dart';

/// Application service for deck lifecycle operations.
///
/// Responsible for creating, reading, updating, and deleting decks and their
/// associated flashcard stats. Post-import enrichment (iNaturalist photos and
/// common names) is handled separately by [EnrichmentService].
class DecksService extends ChangeNotifier {
  final DeckRepository _deckRepository;
  final SpeciesRepository _speciesRepository;
  final FlashCardStatRepository _flashCardStatRepository;
  final ImageService _imageService;

  DecksService(
    this._deckRepository,
    this._flashCardStatRepository,
    this._speciesRepository,
    this._imageService,
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

  Future<List<ViewDeck>> getAllDecks() async {
    final stopwatch = Stopwatch()..start();
    final List<BaseDeck> decks = await _deckRepository.getAllDecks();
    final viewDecks = await _createViewDecks(decks);
    stopwatch.stop();
    if (kDebugMode) {
      debugPrint(
        'DecksService: getAllDecks decks=${decks.length} '
        '(${stopwatch.elapsedMilliseconds}ms)',
      );
    }
    return viewDecks;
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

  Future<void> deleteDeck(String deckId) async {
    await _deleteDeckCoverImage(deckId);
    await _deckRepository.delete(deckId);
    notifyListeners();
  }

  // ── Private helpers ───────────────────────────────────────────────────────

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

  Future<List<BaseDeck>> _getRawDecksByIds(Set<String> deckIds) async {
    return _deckRepository.getDecksByIds(deckIds);
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

  Future<void> _deleteDeckCoverImage(String deckId) async {
    final decks = await _deckRepository.getDecksByIds({deckId});
    if (decks.isEmpty) return;

    final coverImagePath = decks.first.coverImagePath;
    if (coverImagePath == null || coverImagePath.isEmpty) return;
    await _imageService.deleteImage(coverImagePath);
  }
}
