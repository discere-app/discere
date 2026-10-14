import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/repository/deprecated_species_name_repository.dart';
import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/model/deck_update_diff.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/shared/persistence/user_data_writes.dart';

/// Carries out one deck's update against a newer catalog version: works out
/// what would change, and applies the part of it the user accepted.
///
/// The counterpart to `DeckUpdateService`, which answers the other half of
/// the question — *whether* any local deck has a newer version in the online
/// catalog. That one watches the catalog and notifies; this one is handed a
/// single deck and a single remote version and does the work.
///
/// Deliberately not part of `DeckImportService`: an import creates a deck
/// from something the user supplied, an update reconciles a deck that
/// already exists against a newer version of itself. They share neither a
/// caller nor a failure mode, and the update path has its own UI in
/// `decks/edit/deck_update_dialog.dart`.
class DeckUpdateApplier {
  final DecksService _decksService;
  final SpeciesRepository _speciesRepository;
  final DeprecatedSpeciesNameRepository _deprecatedNames;

  const DeckUpdateApplier(
    this._decksService,
    this._speciesRepository, {
    required DeprecatedSpeciesNameRepository deprecatedNames,
    required UserDataWrites userDataWrites,
  }) : _deprecatedNames = deprecatedNames,
       _writes = userDataWrites;

  /// Counts [apply] — read the deck, write it back — as one write sequence
  /// for the in-app restart.
  final UserDataWrites _writes;

  /// Compares [deckId]'s current species against [remote]'s catalog entry,
  /// so the deck-update dialog can show the user what a refresh would add or
  /// remove before applying anything.
  ///
  /// A remote name resolves to an active species first. Only a name no
  /// active species answers to may resolve to a deprecated one, and only to
  /// one the deck already holds: such a species stays, and the update never
  /// adds a deprecated species.
  Future<DeckUpdateDiff> diff(String deckId, CreateDeck remote) async {
    final currentSpecies = await _decksService.getSpeciesByDeckId(deckId);
    final currentIds = currentSpecies.map((s) => s.id).toSet();
    final currentById = {for (final s in currentSpecies) s.id: s};

    final remoteNames = remote.speciesNames?.toList() ?? const <String>[];
    final active = await _speciesRepository.resolveFullNames(remoteNames);
    // A name no active species answers to may still name a deprecated one
    // the deck already holds: the remote deck keeps it, so it stays. Only a
    // species already in the deck, so an update never adds one.
    final resolved = {
      ...await _deprecatedNames.resolveAmong(
        remoteNames.where((name) => !active.containsKey(name)).toList(),
        currentIds,
      ),
      ...active,
    };
    final remoteIds = resolved.values.toSet();

    final addedIds = remoteIds.difference(currentIds);
    final removedIds = currentIds.difference(remoteIds);

    final addedSpecies = addedIds.isEmpty
        ? const <Species>[]
        : await _decksService.getSpeciesByIds(addedIds);
    final removedSpecies = [
      for (final id in removedIds)
        if (currentById[id] != null) currentById[id]!,
    ];
    final unresolvedAddedNames = remoteNames
        .where((name) => !resolved.containsKey(name))
        .toList();

    return DeckUpdateDiff(
      addedSpecies: addedSpecies,
      removedSpecies: removedSpecies,
      unresolvedAddedNames: unresolvedAddedNames,
    );
  }

  /// Applies a previously computed [diff] to [deckId]: name/description/
  /// cover/language are left untouched (a deck update only ever touches
  /// species membership), while `sourceId`/`updatedAt` are always bumped to
  /// [remote]'s values so the deck stops showing as outdated even if the
  /// user declines both the additions and the removals. Returns the names
  /// from [diff.unresolvedAddedNames] that still need background iNaturalist
  /// resolution — empty unless [includeAdditions] is true.
  Future<List<String>> apply({
    required String deckId,
    required CreateDeck remote,
    required DeckUpdateDiff diff,
    required bool includeAdditions,
    required bool includeRemovals,
  }) => _writes.run(() async {
    final current = await _decksService.getCreateDeck(deckId);

    final updatedDeck = BaseDeck(
  id: deckId,
  name: current.name,
  description: current.description,
      coverImagePath: current.coverImagePath,
      language: current.language,
      sourceId: remote.sourceId,
      updatedAt: remote.updatedAt,
    );
    // Only what the diff names: a species of the deck that the reference
    // database does not resolve is in neither list and keeps its progress.
    await _decksService.updateDeck(
      updatedDeck,
      addedSpeciesIds: {
        if (includeAdditions) ...diff.addedSpecies.map((s) => s.id),
      },
      removedSpeciesIds: {
        if (includeRemovals) ...diff.removedSpecies.map((s) => s.id),
      },
    );

    return includeAdditions ? diff.unresolvedAddedNames : const <String>[];
  });
}
