import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/repository/deck_config_repository.dart';
import 'package:discere/learning/repository/deck_merge_repository.dart';
import 'package:discere/learning/repository/subdeck_repository.dart';
import 'package:discere/learning/service/deck_import_service.dart';
import 'package:discere/learning/service/deck_supersession.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/learning/service/favorite_service.dart';
import 'package:discere/shared/persistence/user_data_writes.dart';

/// What merging a catalog entry into the user's decks does, worked out
/// before anything is written, for the user to confirm.
class DeckMergePlan {
  final CreateDeck entry;

  /// The local deck already imported from [entry], or `null` when the merge
  /// imports it first.
  final BaseDeck? target;

  /// The local decks [entry] supersedes, in the order of the deck list.
  final List<BaseDeck> superseded;

  /// Those of [superseded] that go: every entry superseding them is a local
  /// deck once this merge has run. The others keep the species no local
  /// entry holds yet.
  final List<BaseDeck> deleted;

  /// The species of [deleted] decks that no entry superseding them holds —
  /// their progress goes with the deck. Scientific names, sorted.
  final List<String> lostSpeciesNames;

  final DeckSupersession _supersession;

  const DeckMergePlan._({
    required this.entry,
    required this.target,
    required this.superseded,
    required this.deleted,
    required this.lostSpeciesNames,
    required DeckSupersession supersession,
  }) : _supersession = supersession;
}

/// Merges a catalog entry that supersedes local decks into the user's decks:
/// the entry becomes a local deck — the one already imported from it, or a
/// fresh import — and takes over the progress of each superseded deck for
/// the species it holds. Progress follows the species, so one rule covers a
/// changed id (one deck to one), levels joined into one deck, a deck split
/// up, and any mix of these.
///
/// Slice-level rather than in `decks/` or `import/`: the deck list offers a
/// merge for a superseded deck, the online tab for the entry that
/// supersedes it, and both run this.
class DeckMergeService {
  final DecksService _decksService;
  final DeckImportService _importService;
  final DeckMergeRepository _mergeRepository;
  final SubdeckRepository _subdecks;
  final DeckConfigRepository _deckConfigs;
  final FavoriteService _favorites;
  final UserDataWrites _writes;

  DeckMergeService(
    this._decksService,
    this._importService, {
    required DeckMergeRepository mergeRepository,
    required SubdeckRepository subdeckRepository,
    required DeckConfigRepository deckConfigRepository,
    required FavoriteService favoriteService,
    required UserDataWrites userDataWrites,
  }) : _mergeRepository = mergeRepository,
       _subdecks = subdeckRepository,
       _deckConfigs = deckConfigRepository,
       _favorites = favoriteService,
       _writes = userDataWrites;

  /// What merging [entry] would do, against the user's decks as they are
  /// now and the [catalog] it comes from. Writes nothing.
  Future<DeckMergePlan> plan(CreateDeck entry, List<CreateDeck> catalog) async {
    final supersession = DeckSupersession(
      catalog: catalog,
      localDecks: (await _decksService.getDecksBySourceId()).values,
    );
    final superseded = supersession.decksSupersededBy(entry);
    final deleted = [
      for (final deck in superseded)
        if (supersession
            .entriesSuperseding(deck)
            .every(
              (e) =>
                  e.sourceId == entry.sourceId ||
                  supersession.localDeckOf(e) != null,
            ))
          deck,
    ];
    final target = supersession.localDeckOf(entry);
    final lostIds = await _speciesWithoutSuccessor(
      entry,
      target,
      deleted,
      supersession,
    );
    final lost = await _decksService.getSpeciesByIds(lostIds);
    return DeckMergePlan._(
      entry: entry,
      target: target,
      superseded: superseded,
      deleted: deleted,
      lostSpeciesNames: lost.map((s) => s.getBinomialName()).toList()..sort(),
      supersession: supersession,
    );
  }

  /// Carries out [plan] and returns the merged deck, with the result of
  /// importing it when the merge did — for the caller to offer its
  /// download, as after any import.
  ///
  /// Each deck's progress moves in a transaction of its own. A merge that
  /// stops in between is finished by merging again: the target is found by
  /// its `sourceId`, and what has moved already is not there to move twice.
  Future<({String targetDeckId, DeckImportResult? importResult})> merge(
    DeckMergePlan plan,
  ) => _writes.run(() async {
    final existing = plan.target;
    DeckImportResult? imported;
    final String targetId;
    if (existing != null) {
      targetId = existing.id!;
    } else {
      imported = await _importService.importDecks([plan.entry]);
      if (!imported.hasSuccess) throw imported.lastError!;
      targetId = imported.importedDeckIds.single;
    }

    final movedIntoTarget = <String>{};
    for (final deck in plan.superseded) {
      // Into every local deck that supersedes it, not only this target: a
      // merge into another entry that stopped half way would otherwise lose
      // its share once this one deletes the deck.
      for (final entry in plan._supersession.entriesSuperseding(deck)) {
        final into = entry.sourceId == plan.entry.sourceId
            ? targetId
            : plan._supersession.localDeckOf(entry)?.id;
        if (into == null) continue;
        final moved = await _mergeRepository.moveSharedProgress(
          fromDeckId: deck.id!,
          toDeckId: into,
        );
        if (into == targetId) movedIntoTarget.addAll(moved);
      }
    }
    if (imported != null) {
      await _settleImportedTarget(targetId, plan, movedIntoTarget);
    }
    for (final deck in plan.deleted) {
      await _decksService.deleteDeck(deck.id!);
    }
    return (targetDeckId: targetId, importResult: imported);
  });

  /// A freshly imported target takes the place of the decks it replaces:
  /// the settings of the first, the position and favorite mark of the
  /// deleted ones, and only the subdecks the user was learning.
  Future<void> _settleImportedTarget(
    String targetId,
    DeckMergePlan plan,
    Set<String> moved,
  ) async {
    if (plan.superseded.isNotEmpty) {
      final config = await _deckConfigs.getOrDefault(plan.superseded.first.id!);
      await _deckConfigs.save(config.copyWith(deckId: targetId));
    }
    if (plan.deleted.isNotEmpty) {
      await _mergeRepository.takePosition(
        targetId,
        fromDeckId: plan.deleted.first.id!,
      );
    }
    if (plan.deleted.any((deck) => _favorites.isFavoriteDeck(deck.id!)) &&
        !_favorites.isFavoriteDeck(targetId)) {
      _favorites.toggleDeck(targetId);
    }
    // The import switched every subdeck on. Without a moved species in any,
    // there is nothing to say which ones the user wants, so they stay on.
    final subdeckBySpecies = await _subdecks.getSubdeckIdBySpeciesId(targetId);
    final learned = {
      for (final speciesId in moved) ?subdeckBySpecies[speciesId],
    };
    if (learned.isNotEmpty) {
      await _decksService.setActiveSubdecks(targetId, learned);
    }
  }

  /// The species of [deleted] that none of the entries superseding them
  /// holds: [entry]'s by its names, the others' by their local decks.
  Future<Set<String>> _speciesWithoutSuccessor(
    CreateDeck entry,
    BaseDeck? target,
    List<BaseDeck> deleted,
    DeckSupersession supersession,
  ) async {
    if (deleted.isEmpty) return const {};
    final successorIds = {
      for (final deck in deleted)
        for (final e in supersession.entriesSuperseding(deck))
          ?supersession.localDeckOf(e)?.id,
    };
    final speciesByDeckId = await _decksService.getSpeciesIdsGroupedByDeckId({
      ...deleted.map((deck) => deck.id!),
      ...successorIds,
    });
    final entrySpecies = target != null
        ? speciesByDeckId[target.id] ?? const <String>{}
        : (await _importService.resolveSpeciesNames(
            entry.speciesNames?.toList() ?? const [],
          )).values.toSet();
    Set<String> heldBy(CreateDeck e) => e.sourceId == entry.sourceId
        ? entrySpecies
        : speciesByDeckId[supersession.localDeckOf(e)?.id] ?? const {};

    return {
      for (final deck in deleted)
        ...(speciesByDeckId[deck.id] ?? const <String>{}).difference({
          for (final e in supersession.entriesSuperseding(deck)) ...heldBy(e),
        }),
    };
  }
}
