import 'package:discere/enrichment/model/enrichment_capability.dart';
import 'package:discere/enrichment/model/enrichment_work_state.dart';
import 'package:discere/enrichment/pipeline/model/enrichment_work_plan.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_tables.dart';
import 'package:discere/enrichment/pipeline/repository/species_ownership_planner.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:sqflite/sqflite.dart';

/// Which deck owns which enrichment work, and what it has consent for: the
/// species a deck tracks, the taxa those species imply, and the names it
/// could not resolve.
///
/// The one write path that must stay atomic across tables lives here —
/// [assignSpeciesOwners] writes `enrichment_species_work`,
/// `enrichment_species_deck_membership` and
/// `enrichment_species_capability_state` in a single transaction, which is
/// why owner assignment, deck membership and queue seeding are not three
/// repositories. How work items then progress is
/// `EnrichmentWorkClaimRepository`/`EnrichmentWorkOutcomeRepository`'s
/// business, not this one's.
class EnrichmentOwnershipRepository {
  final Database? _injectedDb;

  const EnrichmentOwnershipRepository([this._injectedDb]);

  Future<Database> get _db async => _injectedDb ?? DatabaseHelper.userDb;

  /// Assigns overlapping species to a single owner deck and folds each
  /// deck's consent into the species' `wants_inat_photos`/
  /// `wants_common_names` columns. Both rules — dedup and additive-only
  /// consent — live in [SpeciesOwnershipPlanner]; this applies its plan in
  /// one transaction.
  ///
  /// Also seeds the `base` capability (always) and `speciesCommonNames`
  /// (only if consented) as `pending` queue rows for every species touched —
  /// idempotent, so repeating this for an already-tracked species is a no-op
  /// for capabilities that already exist. `inatPrimary`/`inatBackfill` are
  /// deliberately never seeded here: those are reactive, seeded only once a
  /// worker determines a species needs them (see
  /// `EnrichmentWorkOutcomeRepository.seedCapability`).
  Future<Map<String, List<String>>> assignSpeciesOwners({
    required Map<String, Set<String>> speciesIdsByDeckId,
    required List<String> prioritizedDeckIds,
    Map<String, bool> includeInatPhotosByDeckId = const {},
    Map<String, bool> includeCommonNamesByDeckId = const {},
  }) async {
    final db = await _db;
    return db.transaction((txn) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final plan = SpeciesOwnershipPlanner(
        speciesIdsByDeckId: speciesIdsByDeckId,
        prioritizedDeckIds: prioritizedDeckIds,
        includeInatPhotosByDeckId: includeInatPhotosByDeckId,
        includeCommonNamesByDeckId: includeCommonNamesByDeckId,
        existingSpeciesWorkRows: await txn.query(
          EnrichmentWorkTables.speciesWork,
        ),
        existingMembershipRows: await txn.query(
          EnrichmentWorkTables.deckMembership,
        ),
      ).plan();

      for (final assignment in plan.assignments) {
        await _upsertSpeciesWorkAndCapabilities(
          txn,
          assignment.speciesId,
          ownerDeckId: assignment.ownerDeckId,
          deckIds: assignment.deckIds,
          wantsInatPhotos: assignment.wantsInatPhotos,
          wantsCommonNames: assignment.wantsCommonNames,
          now: now,
        );
      }
      for (final speciesId in plan.droppedSpeciesIds) {
        await txn.delete(
          EnrichmentWorkTables.speciesWork,
          where: 'species_id = ?',
          whereArgs: [speciesId],
        );
        await txn.delete(
          EnrichmentWorkTables.deckMembership,
          where: 'species_id = ?',
          whereArgs: [speciesId],
        );
      }

      return plan.ownedSpeciesByDeckId(prioritizedDeckIds);
    });
  }

  /// Registers a single newly-resolved species as belonging to [deckId] —
  /// the "straggler round" triggered when a name-resolution item succeeds
  /// after the bulk [assignSpeciesOwners] call already ran for the rest of
  /// the deck. Unlike [assignSpeciesOwners] (which treats its input as the
  /// authoritative full deck/species map for every deck it's given, so
  /// calling it with just one species would wipe out any other decks
  /// already tracking it), this additively merges [deckId] into whatever
  /// decks already reference [speciesId] — safe to call one species at a
  /// time without clobbering other decks' membership.
  Future<void> registerResolvedSpeciesForDeck(
    String speciesId,
    String deckId, {
    required bool wantsInatPhotos,
    required bool wantsCommonNames,
  }) async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      final existingRows = await txn.query(
        EnrichmentWorkTables.speciesWork,
        where: 'species_id = ?',
        whereArgs: [speciesId],
      );
      final existingRow = existingRows.isEmpty ? null : existingRows.single;
      final existingMembershipRows = await txn.query(
        EnrichmentWorkTables.deckMembership,
        columns: const ['deck_id'],
        where: 'species_id = ?',
        whereArgs: [speciesId],
      );
      final deckIds = {
        for (final row in existingMembershipRows) row['deck_id'] as String,
        deckId,
      }.toList(growable: false)..sort();
      final ownerDeckId = existingRow?['owner_deck_id'] as String? ?? deckId;
      final wantsInatPhotosResolved =
          (existingRow?['wants_inat_photos'] as int? ?? 0) == 1 ||
          wantsInatPhotos;
      final wantsCommonNamesResolved =
          (existingRow?['wants_common_names'] as int? ?? 0) == 1 ||
          wantsCommonNames;

      await _upsertSpeciesWorkAndCapabilities(
        txn,
        speciesId,
        ownerDeckId: ownerDeckId,
        deckIds: deckIds,
        wantsInatPhotos: wantsInatPhotosResolved,
        wantsCommonNames: wantsCommonNamesResolved,
        now: now,
      );
    });
  }

  Future<void> _upsertSpeciesWorkAndCapabilities(
    DatabaseExecutor txn,
    String speciesId, {
    required String ownerDeckId,
    required List<String> deckIds,
    required bool wantsInatPhotos,
    required bool wantsCommonNames,
    required int now,
  }) async {
    await txn.insert(EnrichmentWorkTables.speciesWork, {
      'species_id': speciesId,
      'owner_deck_id': ownerDeckId,
      'deck_count': deckIds.length,
      'wants_inat_photos': wantsInatPhotos ? 1 : 0,
      'wants_common_names': wantsCommonNames ? 1 : 0,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    for (final deckId in deckIds) {
      await txn.insert(EnrichmentWorkTables.deckMembership, {
        'species_id': speciesId,
        'deck_id': deckId,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    await txn.insert(EnrichmentWorkTables.capabilityState, {
      'species_id': speciesId,
      'capability': EnrichmentCapability.base.wireName,
      'state': pendingState,
      'priority_tier': 0,
      'attempt_count': 0,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    if (wantsCommonNames) {
      await txn.insert(EnrichmentWorkTables.capabilityState, {
        'species_id': speciesId,
        'capability': EnrichmentCapability.speciesCommonNames.wireName,
        'state': pendingState,
        'priority_tier': 20,
        'attempt_count': 0,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    if (wantsInatPhotos) {
      await _catchUpInatFallback(txn, speciesId, now);
    }
  }

  /// Consent can arrive after `base` already resolved, in either shape: the
  /// deck-import flow schedules once with consent withheld (to start `base`
  /// downloads immediately, before the user has even seen the import
  /// dialog) and again with the user's actual choice once they dismiss it;
  /// Edit Deck's "Erneut anreichern" can likewise be the first time a
  /// base-only-enriched deck ever requests iNat data. `BaseWorker`'s own
  /// reactive seed only fires once, exactly when it marks `base` terminal —
  /// a species whose `base` row already exists (in any state) is untouched
  /// by the `base` insert above (`ConflictAlgorithm.ignore`), and nothing
  /// else revisits an already-terminal species. Catches both cases up here,
  /// the other place `wants_inat_photos` can flip from false to true,
  /// mirroring exactly what `BaseWorker` would have seeded had consent been
  /// present at the time `base` resolved:
  /// - `base` resolved without an image (`noResult`/`permanentFailure`):
  ///   iNat becomes the primary source, so both `inatPrimary` (fetch now)
  ///   and `inatBackfill` (nothing left it would supersede) are seeded —
  ///   matches `BaseWorker._seedINatFallback`.
  /// - `base` already succeeded (`done`): the species already has an image,
  ///   so only a low-priority `inatBackfill` is seeded to eventually add an
  ///   iNat photo too — matches `BaseWorker._runOne`'s success branch.
  Future<void> _catchUpInatFallback(
    DatabaseExecutor txn,
    String speciesId,
    int now,
  ) async {
    final baseRows = await txn.query(
      EnrichmentWorkTables.capabilityState,
      columns: const ['state'],
      where: 'species_id = ? AND capability = ?',
      whereArgs: [speciesId, EnrichmentCapability.base.wireName],
      limit: 1,
    );
    if (baseRows.isEmpty) return;
    final baseState = baseRows.single['state'] as String?;
    if (baseState == null || !terminalStates.contains(baseState)) {
      return;
    }
    if (baseState != EnrichmentWorkState.done.wireName) {
      await txn.insert(EnrichmentWorkTables.capabilityState, {
        'species_id': speciesId,
        'capability': EnrichmentCapability.inatPrimary.wireName,
        'state': pendingState,
        'priority_tier': 10,
        'attempt_count': 0,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await txn.insert(EnrichmentWorkTables.capabilityState, {
      'species_id': speciesId,
      'capability': EnrichmentCapability.inatBackfill.wireName,
      'state': pendingState,
      'priority_tier': 40,
      'attempt_count': 0,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// Registers [items] against [EnrichmentWorkTables.taxonomyWork], keyed by
  /// `runtime_entity_key` so multiple calls for the same taxon (from
  /// different species/decks) merge into one row instead of duplicating it.
  /// Each item's species are added to [EnrichmentWorkTables.taxonomyWorkSpecies] via
  /// `INSERT OR IGNORE`, so membership unions automatically across calls
  /// without a read-merge. No deck is tracked: deck scoping is derived from
  /// the species junction joined against [EnrichmentWorkTables.deckMembership].
  Future<void> registerTaxonomyWork({
    required Iterable<TaxonomyWorkPlanItem> items,
  }) async {
    final itemList = items.toList(growable: false);
    if (itemList.isEmpty) return;
    final db = await _db;
    await db.transaction((txn) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      // Load only the rows this call might merge into, keyed by
      // runtime_entity_key, to preserve an existing row's work_key/state
      // rather than scanning the whole taxonomy table on every call.
      final runtimeEntityKeys = [
        for (final item in itemList) item.runtimeEntityKey,
      ];
      final placeholders = List.filled(runtimeEntityKeys.length, '?').join(',');
      final rows = await txn.query(
        EnrichmentWorkTables.taxonomyWork,
        columns: const ['work_key', 'runtime_entity_key', 'common_names_state'],
        where: 'runtime_entity_key IN ($placeholders)',
        whereArgs: runtimeEntityKeys,
      );
      final existingByRuntimeEntityKey = {
        for (final row in rows) row['runtime_entity_key'] as String: row,
      };

      for (final item in itemList) {
        final existingRow = existingByRuntimeEntityKey[item.runtimeEntityKey];
        final workKey = existingRow?['work_key'] as String? ?? item.workKey;
        await txn.insert(EnrichmentWorkTables.taxonomyWork, {
          'work_key': workKey,
          'runtime_entity_key': item.runtimeEntityKey,
          'common_names_state': existingRow?['common_names_state'] ?? pendingState,
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        for (final speciesId in item.speciesIds) {
          await txn.insert(EnrichmentWorkTables.taxonomyWorkSpecies, {
            'work_key': workKey,
            'species_id': speciesId,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }
    });
  }

  Future<void> releaseDeck(String deckId) async {
    final normalizedDeckId = deckId.trim();
    if (normalizedDeckId.isEmpty) return;
    final db = await _db;
    await db.transaction((txn) async {
      final membershipRows = await txn.query(
        EnrichmentWorkTables.deckMembership,
        columns: const ['species_id'],
        where: 'deck_id = ?',
        whereArgs: [normalizedDeckId],
      );
      final affectedSpeciesIds = {
        for (final row in membershipRows) row['species_id'] as String,
      };
      await txn.delete(
        EnrichmentWorkTables.deckMembership,
        where: 'deck_id = ?',
        whereArgs: [normalizedDeckId],
      );

      for (final speciesId in affectedSpeciesIds) {
        final speciesRows = await txn.query(
          EnrichmentWorkTables.speciesWork,
          where: 'species_id = ?',
          whereArgs: [speciesId],
        );
        if (speciesRows.isEmpty) continue;
        final ownerDeckId = speciesRows.single['owner_deck_id'] as String?;
        final remainingMembership = await txn.query(
          EnrichmentWorkTables.deckMembership,
          columns: const ['deck_id'],
          where: 'species_id = ?',
          whereArgs: [speciesId],
        );
        if (remainingMembership.isEmpty) {
          // No deck references this species anymore (the departing deck's
          // own membership rows were already deleted above) — nothing left
          // to track.
          await txn.delete(
            EnrichmentWorkTables.speciesWork,
            where: 'species_id = ?',
            whereArgs: [speciesId],
          );
          continue;
        }
        // Other decks still reference this species. owner_deck_id is pure
        // tie-break bookkeeping for assignSpeciesOwners' dedup contract, not
        // exclusive control — a still-referencing deck must never lose its
        // tracking just because the departing deck happened to be the
        // arbitrary owner. Reassign ownership to one of the remaining decks
        // if the departing deck held it, instead of discarding the row.
        final newOwnerDeckId = ownerDeckId == normalizedDeckId
            ? remainingMembership.first['deck_id'] as String
            : ownerDeckId;
        await txn.update(
          EnrichmentWorkTables.speciesWork,
          {
            'owner_deck_id': newOwnerDeckId,
            'deck_count': remainingMembership.length,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'species_id = ?',
          whereArgs: [speciesId],
        );
      }

      // Taxonomy work is not touched here: it carries no deck association
      // (deck scoping is derived from the species junction joined against
      // deckMembership), and the claim guard skips any taxonomy row whose
      // species no longer have a membership, so an orphaned row simply sits as
      // permanent dedup cache instead of needing per-deck GC.

      await txn.delete(
        EnrichmentWorkTables.unresolvedNames,
        where: 'deck_id = ?',
        whereArgs: [normalizedDeckId],
      );
    });
  }

  /// Seeds `pending` rows in [EnrichmentWorkTables.unresolvedNames] for scientific names that
  /// couldn't be resolved against the reference DB at schedule time. ORs
  /// [wantsInatPhotos]/[wantsCommonNames] onto any already-tracked row for
  /// the same (deckId, name) pair, and preserves its retry progress — same
  /// additive-consent, no-reset-on-reschedule contract as
  /// [assignSpeciesOwners].
  Future<void> seedUnresolvedNames(
    String deckId,
    Iterable<String> names, {
    required bool wantsInatPhotos,
    required bool wantsCommonNames,
  }) async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      for (final name in names) {
        final existing = await txn.query(
          EnrichmentWorkTables.unresolvedNames,
          where: 'deck_id = ? AND name = ?',
          whereArgs: [deckId, name],
        );
        final existingRow = existing.isEmpty ? null : existing.first;
        final alreadyWantsInatPhotos =
            (existingRow?['wants_inat_photos'] as int? ?? 0) == 1;
        final alreadyWantsCommonNames =
            (existingRow?['wants_common_names'] as int? ?? 0) == 1;
        await txn.insert(EnrichmentWorkTables.unresolvedNames, {
          'deck_id': deckId,
          'name': name,
          'state': existingRow?['state'] ?? pendingState,
          'wants_inat_photos': (wantsInatPhotos || alreadyWantsInatPhotos)
              ? 1
              : 0,
          'wants_common_names': (wantsCommonNames || alreadyWantsCommonNames)
              ? 1
              : 0,
          'attempt_count': existingRow?['attempt_count'] ?? 0,
          'next_attempt_at': existingRow?['next_attempt_at'],
          'last_error': existingRow?['last_error'],
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  /// Every species set currently tracked in [EnrichmentWorkTables.deckMembership], keyed by
  /// deck id. Used when scheduling new decks so their species-owner
  /// assignment call ([assignSpeciesOwners]) can include already-tracked
  /// decks as lower-priority input — without this, a species already owned
  /// by a still-in-flight deck could get silently reassigned to a new deck
  /// that merely happens to share it.
  Future<Map<String, Set<String>>> loadAllDeckSpeciesSnapshots() async {
    final db = await _db;
    final rows = await db.query(EnrichmentWorkTables.deckMembership);
    final result = <String, Set<String>>{};
    for (final row in rows) {
      final deckId = row['deck_id'] as String;
      final speciesId = row['species_id'] as String;
      result.putIfAbsent(deckId, () => <String>{}).add(speciesId);
    }
    return result;
  }

}
