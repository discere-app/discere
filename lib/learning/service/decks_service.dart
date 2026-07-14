import 'package:flutter/foundation.dart';

import 'package:discere/catalog/model/species.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/learning/model/deck_stat.dart';
import 'package:discere/learning/model/flashcard_stat.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/model/view_deck.dart';
import 'package:discere/learning/repository/deck_config_repository.dart';
import 'package:discere/learning/repository/deck_repository.dart';
import 'package:discere/learning/repository/flashcard_stat_repository.dart';
import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/shared/service/image_service.dart';

/// Application service for deck lifecycle operations.
///
/// Responsible for creating, reading, updating, and deleting decks and their
/// associated flashcard stats. Post-import enrichment (iNaturalist photos and
/// common names) is handled separately by [EnrichmentService].
class DecksService extends ChangeNotifier {
  static final _log = Logger.forType(DecksService);
  static int _suppressedNotificationDepth = 0;
  final DeckRepository _deckRepository;
  final SpeciesRepository _speciesRepository;
  final FlashcardStatRepository _flashcardStatRepository;
  final ImageService _imageService;
  final DeckConfigRepository? _deckConfigRepository;

  /// Called after a deck is deleted, so other services can clean up.
  void Function(String deckId)? onDeckDeleted;

  /// Called after a deck is created (manually or via import).
  /// Receives the new deck ID so other services can initialize per-deck state.
  void Function(String deckId)? onDeckCreated;

  DecksService(
    this._deckRepository,
    this._flashcardStatRepository,
    this._speciesRepository,
    this._imageService, {
    DeckConfigRepository? deckConfigRepository,
  }) : _deckConfigRepository = deckConfigRepository;

  static Future<T> runWithNotificationsSuppressed<T>(
    Future<T> Function() action,
  ) async {
    _suppressedNotificationDepth++;
    try {
      return await action();
    } finally {
      _suppressedNotificationDepth--;
    }
  }

  void notifyDecksChanged() {
    notifyListeners();
  }

  Future<String> createDeck(CreateDeck deck) async {
    _log.debug(
      'Create deck name="${deck.name}" species=${deck.speciesIds?.length ?? 0}',
    );
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
    onDeckCreated?.call(id);
    _notifyListenersIfEnabled();
    return id;
  }

  Future<void> updateDeck(
    BaseDeck updatedDeck,
    Set<String> newSpeciesIds,
  ) async {
    // 1. Upsert deck metadata (insertDeck uses conflictAlgorithm: replace)
    await _deckRepository.insertDeck(updatedDeck);

    // 2. Diff species list
    final currentIds = await _flashcardStatRepository.getSpeciesIdsByDeckId(
      updatedDeck.id!,
    );
    final removed = currentIds.difference(newSpeciesIds);
    final added = newSpeciesIds.difference(currentIds);

    // 3. Remove flash-card stats for removed species
    if (removed.isNotEmpty) {
      await _flashcardStatRepository.deleteFlashcardStats(
        updatedDeck.id!,
        removed,
      );
    }

    // 4. Insert flash-card stats for newly added species (preserves progress for existing)
    if (added.isNotEmpty) {
      final newStats = added
          .map(
            (speciesId) =>
                FlashcardStat(speciesId: speciesId, deckId: updatedDeck.id!),
          )
          .toSet();
      await _flashcardStatRepository.insertOrUpdateFlashcardStats(newStats);
    }

    _notifyListenersIfEnabled();
  }

  Future<List<ViewDeck>> getAllDecks() async {
    final stopwatch = Stopwatch()..start();
    final List<BaseDeck> decks = await _deckRepository.getAllDecks();
    final viewDecks = await _createViewDecks(decks);
    stopwatch.stop();
    _log.debug(
      'getAllDecks decks=${decks.length} '
      '(${stopwatch.elapsedMilliseconds}ms)',
    );
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
    final speciesIds = await _flashcardStatRepository.getSpeciesIdsByDeckId(
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

  Future<List<BaseDeck>> getDecksForSpecies(String speciesId) async {
    final deckIds = await _flashcardStatRepository.getDeckIdsBySpeciesId(
      speciesId,
    );
    if (deckIds.isEmpty) return [];
    return _deckRepository.getDecksByIds(deckIds);
  }

  Future<Set<String>> getSpeciesIdsByDeckIds(Iterable<String> deckIds) async {
    final speciesIds = <String>{};
    for (final deckId in deckIds) {
      speciesIds.addAll(
        await _flashcardStatRepository.getSpeciesIdsByDeckId(deckId),
      );
    }
    return speciesIds;
  }

  Future<void> deleteDeck(String deckId) async {
    _log.debug('Delete deck deckId=$deckId');
    await _deleteDeckCoverImage(deckId);
    await _deckRepository.delete(deckId);
    onDeckDeleted?.call(deckId);
    _notifyListenersIfEnabled();
  }

  /// Adds new species to an existing deck without removing existing ones.
  /// Used by the enrichment queue to add species resolved via iNaturalist after import.
  Future<void> addSpeciesToDeck(String deckId, Set<String> speciesIds) async {
    if (speciesIds.isEmpty) return;
    final decks = await _deckRepository.getDecksByIds({deckId});
    if (decks.isEmpty) {
      _log.debug(
        'Skip add species to deleted deck deckId=$deckId count=${speciesIds.length}',
      );
      return;
    }
    _log.debug('Add species to deck deckId=$deckId count=${speciesIds.length}');
    final newStats = speciesIds
        .map((id) => FlashcardStat(speciesId: id, deckId: deckId))
        .toSet();
    await _flashcardStatRepository.insertOrUpdateFlashcardStats(newStats);
    _notifyListenersIfEnabled();
  }

  Future<void> updateDeckCoverPath(String deckId, String coverImagePath) async {
    _log.debug('Update deck cover deckId=$deckId path=$coverImagePath');
    final decks = await _deckRepository.getDecksByIds({deckId});
    if (decks.isEmpty) {
      _log.debug('Skip cover update for deleted deck deckId=$deckId');
      return;
    }

    final deck = decks.first;
    if (deck.coverImagePath == coverImagePath) {
      return;
    }

    deck.coverImagePath = coverImagePath;
    await _deckRepository.insertDeck(deck);
    _notifyListenersIfEnabled();
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  Future<void> _initializeDeck(CreateDeck deck) async {
    final speciesIds = deck.speciesIds ?? {};
    if (speciesIds.isEmpty) return;

    final Set<FlashcardStat> flashcardStats = speciesIds
        .map(
          (speciesId) => FlashcardStat(speciesId: speciesId, deckId: deck.id!),
        )
        .toSet();

    await _flashcardStatRepository.insertOrUpdateFlashcardStats(flashcardStats);
  }

  Future<List<BaseDeck>> _getRawDecksByIds(Set<String> deckIds) async {
    return _deckRepository.getDecksByIds(deckIds);
  }

  Future<List<ViewDeck>> _createViewDecks(List<BaseDeck> decks) async {
    final List<ViewDeck> viewDecks = [];
    for (BaseDeck deck in decks) {
      final learningMode = _deckConfigRepository != null
          ? (await _deckConfigRepository.getOrDefault(deck.id!)).learningMode
          : LearningMode.species;
      DeckStat deckStat = await _flashcardStatRepository.getDeckStat(deck.id!);

      double progress = deckStat.uninitializedCount == 0
          ? 1
          : 1 - (deckStat.uninitializedCount / deckStat.totalCount);
      viewDecks.add(
        ViewDeck.fromBase(deck, progress, learningMode: learningMode),
      );
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

  void _notifyListenersIfEnabled() {
    if (_suppressedNotificationDepth == 0) {
      notifyListeners();
    }
  }
}
