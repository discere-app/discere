import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/model/subdeck_membership.dart';
import 'package:discere/learning/model/subdeck_structure.dart';
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

  /// The subdecks of the merged deck, in their order; empty when it has
  /// none.
  final List<SubdeckHeading> subdecks;

  /// How the merged deck's species lie in [subdecks].
  final SubdeckMembership subdeckMembership;

  /// Those of [subdecks] suggested to be on after the merge: the ones the
  /// species whose progress moves into the target are in, and for a
  /// [target] already imported those it has on. For a fresh import all of
  /// them when no such species is in one — nothing then says which ones the
  /// user wants.
  final Set<String> suggestedActiveSubdeckIds;

  final DeckSupersession _supersession;

  const DeckMergePlan._({
    required this.entry,
    required this.target,
    required this.superseded,
    required this.deleted,
    required this.lostSpeciesNames,
    required this.subdecks,
    required this.subdeckMembership,
    required this.suggestedActiveSubdeckIds,
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
    final speciesByDeckId = await _decksService.getSpeciesIdsGroupedByDeckId({
      ?target?.id,
      for (final deck in superseded) ...[
        deck.id!,
        for (final e in supersession.entriesSuperseding(deck))
          ?supersession.localDeckOf(e)?.id,
      ],
    });
    final merged = await _mergedSubdecks(entry, target, speciesByDeckId);
    final handover = supersession.speciesHandover(
      entry,
      entrySpecies: merged.speciesIds,
      speciesByDeckId: speciesByDeckId,
    );
    final lost = await _decksService.getSpeciesByIds({
      for (final deck in deleted) ...?handover.leftByDeckId[deck.id],
    });
    final learned = {
      for (final speciesId in handover.intoEntry)
        ?merged.subdeckIdBySpeciesId[speciesId],
    };
    return DeckMergePlan._(
      entry: entry,
      target: target,
      superseded: superseded,
      deleted: deleted,
      lostSpeciesNames: lost.map((s) => s.getBinomialName()).toList()..sort(),
      subdecks: merged.subdecks,
      subdeckMembership: SubdeckMembership.of(
        merged.speciesIds,
        merged.subdeckIdBySpeciesId,
      ),
      suggestedActiveSubdeckIds: _suggestedActiveSubdecks(
        target,
        active: merged.activeSubdeckIds,
        learned: learned,
      ),
      supersession: supersession,
    );
  }

  /// Carries out [plan] and returns the merged deck, with the result of
  /// importing it when the merge did — for the caller to offer its
  /// download, as after any import. Of the merged deck's subdecks, exactly
  /// [activeSubdeckIds] are on afterwards; a deck without subdecks has none
  /// to switch.
  ///
  /// Each deck's progress moves in a transaction of its own. A merge that
  /// stops in between is finished by merging again: the target is found by
  /// its `sourceId`, and what has moved already is not there to move twice.
  Future<({String targetDeckId, DeckImportResult? importResult})> merge(
    DeckMergePlan plan, {
    required Set<String> activeSubdeckIds,
  }) => _writes.run(() async {
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

    for (final deck in plan.superseded) {
      // Into every local deck that supersedes it, not only this target: a
      // merge into another entry that stopped half way would otherwise lose
      // its share once this one deletes the deck.
      for (final entry in plan._supersession.entriesSuperseding(deck)) {
        final into = entry.sourceId == plan.entry.sourceId
            ? targetId
            : plan._supersession.localDeckOf(entry)?.id;
        if (into == null) continue;
        await _mergeRepository.moveSharedProgress(
          fromDeckId: deck.id!,
          toDeckId: into,
        );
      }
    }
    // After the moves: each switches on the target's subdecks of what it
    // moves, and the user's choice has the last word.
    if (plan.subdecks.isNotEmpty) {
      await _decksService.setActiveSubdecks(targetId, activeSubdeckIds);
    }
    if (imported != null) {
      await _settleImportedTarget(targetId, plan);
    }
    for (final deck in plan.deleted) {
      await _decksService.deleteDeck(deck.id!);
    }
    return (targetDeckId: targetId, importResult: imported);
  });

  /// A freshly imported target takes the place of the decks it replaces:
  /// the settings of the first, the position and favorite mark of the
  /// deleted ones.
  Future<void> _settleImportedTarget(
    String targetId,
    DeckMergePlan plan,
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
  }

  /// [DeckMergePlan.suggestedActiveSubdeckIds], from the subdecks the
  /// merged deck has [active] and the ones the species whose progress moves
  /// into it are in ([learned]).
  Set<String> _suggestedActiveSubdecks(
    BaseDeck? target, {
    required Set<String> active,
    required Set<String> learned,
  }) {
    // An imported target keeps what it has on and gains what was learned.
    if (target != null) return {...active, ...learned};
    // A fresh import keeps only what was learned...
    if (learned.isNotEmpty) return learned;
    // ...and, with nothing to say which ones the user wants, all of them.
    return active;
  }

  /// The species of the merged deck and its subdecks, with the ones it has
  /// on: [target]'s as stored or — for [entry] not imported yet — what
  /// importing it would store, with all of them on.
  Future<
    ({
      Set<String> speciesIds,
      List<SubdeckHeading> subdecks,
      Map<String, String> subdeckIdBySpeciesId,
      Set<String> activeSubdeckIds,
    })
  >
  _mergedSubdecks(
    CreateDeck entry,
    BaseDeck? target,
    Map<String, Set<String>> speciesByDeckId,
  ) async {
    if (target == null) {
      final resolved = await _importService.resolveSpeciesNames(
        entry.speciesNames?.toList() ?? const [],
      );
      final structure = SubdeckStructure.resolve(entry.subdecks, resolved);
      return (
        speciesIds: resolved.values.toSet(),
        subdecks: structure.subdecks,
        subdeckIdBySpeciesId: structure.subdeckIdBySpeciesId,
        activeSubdeckIds: {
          for (final subdeck in structure.subdecks) subdeck.id,
        },
      );
    }
    final stored = await _subdecks.getSubdecks(target.id!);
    return (
      speciesIds: speciesByDeckId[target.id] ?? const <String>{},
      subdecks: [for (final s in stored) (id: s.id, name: s.name)],
      subdeckIdBySpeciesId: await _subdecks.getSubdeckIdBySpeciesId(
        target.id!,
      ),
      activeSubdeckIds: {
        for (final s in stored)
          if (s.isActive) s.id,
      },
    );
  }
}
