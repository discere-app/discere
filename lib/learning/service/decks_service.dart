import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/learning/decks/deck_view_model.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/model/deck_stat.dart';
import 'package:discere/learning/model/flashcard_stat.dart';
import 'package:discere/learning/repository/deck_config_repository.dart';
import 'package:discere/learning/repository/deck_repository.dart';
import 'package:discere/learning/repository/flashcard_stat_repository.dart';
import 'package:discere/learning/service/answerable_cards_service.dart';
import 'package:discere/learning/service/deck_lifecycle_observer.dart';
import 'package:discere/shared/persistence/closed_database_tolerance.dart';
import 'package:discere/shared/persistence/user_data_writes.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:flutter/foundation.dart';

/// Application service for deck lifecycle operations.
///
/// Responsible for creating, reading, updating, and deleting decks and their
/// associated flashcard stats. Post-import enrichment (iNaturalist photos and
/// common names) is handled separately by the enrichment pipeline.
class DecksService extends ChangeNotifier {
  static final _log = Logger.forType(DecksService);
  static int _suppressedNotificationDepth = 0;
  final DeckRepository _deckRepository;
  final SpeciesRepository _speciesRepository;
  final FlashcardStatRepository _flashcardStatRepository;
  final ImageService _imageService;
  final DeckConfigRepository _deckConfigRepository;
  final DeckLifecycleObserver _lifecycleObserver;
  final AnswerableCardsService _answerableCards;

  /// Counts the deck writes that take more than one statement — creating,
  /// updating, deleting, adding species — for the in-app restart.
  final UserDataWrites _writes;

  DecksService(
    this._deckRepository,
    this._flashcardStatRepository,
    this._speciesRepository,
    this._imageService, {
    required DeckConfigRepository deckConfigRepository,
    required DeckLifecycleObserver lifecycleObserver,
    required AnswerableCardsService answerableCards,
    required UserDataWrites userDataWrites,
  }) : _deckConfigRepository = deckConfigRepository,
       _lifecycleObserver = lifecycleObserver,
       _answerableCards = answerableCards,
       _writes = userDataWrites;

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

  Future<String> createDeck(CreateDeck deck) =>
      _writes.run(() => _createDeck(deck));

  Future<String> _createDeck(CreateDeck deck) async {
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
      sourceId: deck.sourceId,
      updatedAt: deck.updatedAt,
      coverImagePath: deck.coverImagePath,
    );

    await _initializeDeck(updatedDeck);
    _lifecycleObserver.onDeckCreated(id);
    _notifyListenersIfEnabled();
    return id;
  }

  /// Writes [updatedDeck]'s metadata and the change to its species: the
  /// cards of [removedSpeciesIds] go, [addedSpeciesIds] get new ones.
  ///
  /// A change rather than the complete species set on purpose. The deck can
  /// hold species the reference database does not resolve — after a failed
  /// alias migration, or a species missing from a release — and no caller
  /// that reads the deck's species sees those. A complete set built from
  /// what it saw would delete their learning progress on every save.
  Future<void> updateDeck(
    BaseDeck updatedDeck, {
    required Set<String> addedSpeciesIds,
    required Set<String> removedSpeciesIds,
  }) => _writes.run(
    () => _updateDeck(updatedDeck, addedSpeciesIds, removedSpeciesIds),
  );

  Future<void> _updateDeck(
    BaseDeck updatedDeck,
    Set<String> addedSpeciesIds,
    Set<String> removedSpeciesIds,
  ) async {
    // 1. Upsert deck metadata (insertDeck uses conflictAlgorithm: replace)
    await _deckRepository.insertDeck(updatedDeck);

    // 2. A species the deck already holds keeps its card and progress.
    final currentIds = await _flashcardStatRepository.getSpeciesIdsByDeckId(
      updatedDeck.id!,
    );
    final removed = removedSpeciesIds.intersection(currentIds);
    final added = addedSpeciesIds.difference(currentIds);

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

  /// Removes a single species from a deck without touching the rest of its
  /// membership — used when the user decides to drop a species that has no
  /// findable photo instead of editing the whole deck.
  Future<void> removeSpeciesFromDeck(String deckId, String speciesId) async {
    await _flashcardStatRepository.deleteFlashcardStats(deckId, {speciesId});
    _notifyListenersIfEnabled();
  }

  Future<List<DeckViewModel>> getAllDecks() async {
    final stopwatch = Stopwatch()..start();
    final List<BaseDeck> decks = await _deckRepository.getAllDecks();
    final viewModels = await _toViewModels(decks);
    stopwatch.stop();
    _log.debug(
      'getAllDecks decks=${decks.length} '
      '(${stopwatch.elapsedMilliseconds}ms)',
    );
    return viewModels;
  }

  Future<List<DeckViewModel>> getDecks(Set<String> deckIds) async {
    final List<BaseDeck> decks = await _getRawDecksByIds(deckIds);
    return await _toViewModels(decks);
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
      sourceId: deck.sourceId,
      updatedAt: deck.updatedAt,
      coverImagePath: deck.coverImagePath,
    );
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

  /// Distinct species across every deck — used by the diagnostics page's
  /// catalog-size metric.
  Future<int> getTotalDistinctSpeciesCount() =>
      _flashcardStatRepository.getTotalDistinctSpeciesCount();

  /// Local decks that carry a catalog `sourceId`, keyed by that id — used to
  /// tell an online catalog entry apart from a deck already imported from it
  /// (e.g. so the "Online" import tab can offer an update instead of a
  /// duplicate import).
  Future<Map<String, BaseDeck>> getDecksBySourceId() async {
    final decks = await _deckRepository.getAllDecks();
    return {
      for (final deck in decks)
        if (deck.sourceId != null) deck.sourceId!: deck,
    };
  }

  Future<List<BaseDeck>> getDecksForSpecies(String speciesId) async {
    final deckIds = await _flashcardStatRepository.getDeckIdsBySpeciesId(
      speciesId,
    );
    if (deckIds.isEmpty) return [];
    return _deckRepository.getDecksByIds(deckIds);
  }

  /// The species of each of [deckIds], keyed by deck id, in one query. A
  /// deck without species is missing from the result.
  Future<Map<String, Set<String>>> getSpeciesIdsGroupedByDeckId(
    Iterable<String> deckIds,
  ) {
    return _flashcardStatRepository.getSpeciesIdsGroupedByDeckId(deckIds);
  }

  Future<void> deleteDeck(String deckId) =>
      _writes.run(() => _deleteDeck(deckId));

  Future<void> _deleteDeck(String deckId) async {
    _log.debug('Delete deck deckId=$deckId');
    // The swipe-to-delete handler doesn't await this, so it can outlive the
    // user database.
    final deleted = await runToleratingClosedDatabase(_log, () async {
      await _deleteDeckCoverImage(deckId);
      // deck_config/flashcard_stats declare ON DELETE CASCADE on deck_id, so
      // this alone removes their rows too — see DatabaseHelper.userDb.
      await _deckRepository.delete(deckId);
    });
    if (!deleted) return;
    _lifecycleObserver.onDeckDeleted(deckId);
    _notifyListenersIfEnabled();
  }

  /// Adds new species to an existing deck without removing existing ones.
  /// Used by the enrichment queue to add species resolved via iNaturalist after import.
  Future<void> addSpeciesToDeck(String deckId, Set<String> speciesIds) =>
      _writes.run(() => _addSpeciesToDeck(deckId, speciesIds));

  Future<void> _addSpeciesToDeck(
    String deckId,
    Set<String> speciesIds,
  ) async {
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

    await _deckRepository.insertDeck(
      deck.copyWith(coverImagePath: coverImagePath),
    );
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

  Future<List<DeckViewModel>> _toViewModels(List<BaseDeck> decks) async {
    final List<DeckViewModel> viewModels = [];
    for (BaseDeck deck in decks) {
      final config = await _deckConfigRepository.getOrDefault(deck.id!);
      final learningMode = config.learningMode;
      final nameType = config.nameType;
      final reviewMode = config.reviewMode;
      // Reads only: deckStat counts the deck's species rather than this
      // combination's rows, so rendering the list does not have to write the
      // rows first. Seeding them belongs to the paths that need the rows
      // themselves — sourcing due cards and initializing a batch.
      DeckStat deckStat = await _answerableCards.deckStat(
        deck.id!,
        learningMode: learningMode,
        nameType: nameType,
      );

      // A deck without a card in its mode — empty, or none of its species
      // has an answer there — has learned nothing, not everything.
      double progress = deckStat.totalCount == 0
          ? 0
          : 1 - (deckStat.uninitializedCount / deckStat.totalCount);
      viewModels.add(
        DeckViewModel(
          stored: deck,
          progress: progress,
          learningMode: learningMode,
          nameType: nameType,
          reviewMode: reviewMode,
        ),
      );
    }
    return viewModels;
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
