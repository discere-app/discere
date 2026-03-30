import 'package:flutter/material.dart';

import '../../model/learning/base_deck.dart';
import '../../model/learning/deck_stat.dart';
import '../../model/learning/flash_card_stat.dart';
import '../../model/ui/create_deck.dart';
import '../../model/ui/view_deck.dart';
import '../../persistence/deck_repository.dart';
import '../../persistence/flash_card_stat_repository.dart';
import '../../persistence/species_repository.dart';
import '../common/image_service.dart';
import '../../model/biology/species.dart';

class DecksService extends ChangeNotifier {
  final DeckRepository _deckRepository;
  final SpeciesRepository _speciesRepository;
  final FlashCardStatRepository _flashCardStatRepository;
  final ImageService _imageService;

  DecksService(this._deckRepository, this._flashCardStatRepository,
      this._speciesRepository, this._imageService);

  Future<void> createDeck(CreateDeck deck) async {
    final id = await _deckRepository.insertDeck(deck);
    // Ensure the deck object has the ID for initialization
    final updatedDeck = CreateDeck(
      id: id,
      name: deck.name,
      description: deck.description,
      speciesIds: deck.speciesIds,
    )..coverImagePath = deck.coverImagePath;

    await _initializeDeck(updatedDeck);
    notifyListeners();
  }

  Future<void> updateDeck(
      BaseDeck updatedDeck, Set<String> newSpeciesIds) async {
    // 1. Upsert deck metadata (insertDeck uses conflictAlgorithm: replace)
    await _deckRepository.insertDeck(updatedDeck);

    // 2. Diff species list
    final currentIds =
        await _flashCardStatRepository.getSpeciesIdsByDeckId(updatedDeck.id!);
    final removed = currentIds.difference(newSpeciesIds);
    final added = newSpeciesIds.difference(currentIds);

    // 3. Remove flash-card stats for removed species
    if (removed.isNotEmpty) {
      await _flashCardStatRepository.deleteFlashCardStats(
          updatedDeck.id!, removed);
    }

    // 4. Insert flash-card stats for newly added species (preserves progress for existing)
    if (added.isNotEmpty) {
      final newStats = added.map((speciesId) => FlashCardStat(
        speciesId: speciesId,
        deckId: updatedDeck.id!,
      )).toSet();
      await _flashCardStatRepository.insertOrUpdateFlashCardStats(newStats);
    }

    notifyListeners();
  }

  Future<void> _initializeDeck(CreateDeck deck) async {
    final speciesIds = deck.speciesIds ?? {};
    if (speciesIds.isEmpty) return;

    final Set<FlashCardStat> flashCardStats = speciesIds.map((speciesId) => FlashCardStat(
      speciesId: speciesId,
      deckId: deck.id!,
    )).toSet();

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
      speciesNames: speciesNames,
      speciesIds: speciesIds,
    )..coverImagePath = deck.coverImagePath;
  }

  Future<List<Species>> getSpeciesByDeckId(String deckId) async {
    final speciesIds =
        await _flashCardStatRepository.getSpeciesIdsByDeckId(deckId);
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
}
