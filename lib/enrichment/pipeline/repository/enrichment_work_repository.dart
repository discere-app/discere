import 'package:discere/enrichment/pipeline/model/enrichment_work_plan.dart';
import 'package:discere/enrichment/pipeline/model/enrichment_work_state_count.dart';
import 'package:discere/enrichment/pipeline/model/inat_work_item.dart';
import 'package:discere/enrichment/queue/model/deck_enrichment_projection.dart';
import 'package:discere/enrichment/queue/repository/enrichment_job_repository.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:sqflite/sqflite.dart';

/// Terminal-state vocabulary shared by the three new producer-consumer queue
/// tables (`enrichment_species_capability_state`, `enrichment_taxonomy_work`,
/// `enrichment_unresolved_names`) — see GitHub issue #57.
const _capabilityStatePending = 'pending';
const _capabilityStateRetryScheduled = 'retryScheduled';
const _capabilityStateTerminal = {'done', 'noResult', 'permanentFailure'};

class EnrichmentWorkRepository {
  static const speciesWorkTable = 'enrichment_species_work';
  static const taxonomyWorkTable = 'enrichment_taxonomy_work';
  static const taxonomyWorkSpeciesTable = 'enrichment_taxonomy_work_species';
  static const capabilityStateTable = 'enrichment_species_capability_state';
  static const deckMembershipTable = 'enrichment_species_deck_membership';
  static const unresolvedNamesTable = 'enrichment_unresolved_names';

  final Database? _injectedDb;

  const EnrichmentWorkRepository([this._injectedDb]);

  Future<Database> get _db async => _injectedDb ?? DatabaseHelper.userDb;

  /// Assigns overlapping species to a single owner deck (unchanged dedup
  /// contract), and additionally OR's [includeInatPhotosByDeckId]/
  /// [includeCommonNamesByDeckId] onto each species' `wants_inat_photos`/
  /// `wants_common_names` columns — additive-only, never a downgrade, so a
  /// species already granted consent by one deck keeps it even if another
  /// deck referencing it opts out. A deck missing from either map is treated
  /// as consenting (matches `EnrichmentJobPayload`'s existing
  /// `includeINatPhotos`/`includeCommonNames` defaults) — callers that don't
  /// yet know per-deck consent can omit these maps entirely.
  ///
  /// Also seeds the `base` capability (always) and `speciesCommonNames`
  /// capability (only if consented) as `pending` queue rows for every
  /// species this call touches — idempotent, so calling this repeatedly for
  /// an already-tracked species is a no-op for capabilities that already
  /// exist. `inatPrimary`/`inatBackfill` are deliberately never seeded here:
  /// those are reactive, seeded only once a worker actually determines a
  /// species needs them (see `seedCapability`).
  Future<Map<String, List<String>>> assignSpeciesOwners({
    required Map<String, Set<String>> speciesIdsByDeckId,
    required List<String> prioritizedDeckIds,
    Map<String, bool> includeInatPhotosByDeckId = const {},
    Map<String, bool> includeCommonNamesByDeckId = const {},
  }) async {
    final db = await _db;
    return db.transaction((txn) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final existingRows = await txn.query(speciesWorkTable);
      final existingBySpeciesId = {
        for (final row in existingRows) row['species_id'] as String: row,
      };
      final existingMembershipRows = await txn.query(deckMembershipTable);
      final existingDeckIdsBySpecies = <String, List<String>>{};
      for (final row in existingMembershipRows) {
        (existingDeckIdsBySpecies[row['species_id'] as String] ??= []).add(
          row['deck_id'] as String,
        );
      }
      final assignments = <String, List<String>>{
        for (final deckId in prioritizedDeckIds) deckId: <String>[],
      };
      final deckPriority = <String, int>{
        for (var index = 0; index < prioritizedDeckIds.length; index++)
          prioritizedDeckIds[index]: index,
      };

      // Count each species' deck frequency once up front. Recomputing it
      // inside the sort comparator would rescan every deck's species set on
      // every comparison — O(n · deckCount · log n) for the whole list.
      final speciesFrequency = <String, int>{};
      for (final speciesIds in speciesIdsByDeckId.values) {
        for (final speciesId in speciesIds) {
          speciesFrequency[speciesId] = (speciesFrequency[speciesId] ?? 0) + 1;
        }
      }
      final allSpeciesIds = speciesFrequency.keys.toList(growable: false)
        ..sort((left, right) {
          final frequencyComparison = (speciesFrequency[right] ?? 0).compareTo(
            speciesFrequency[left] ?? 0,
          );
          if (frequencyComparison != 0) {
            return frequencyComparison;
          }
          return left.compareTo(right);
        });

      for (final speciesId in allSpeciesIds) {
        final deckIds = prioritizedDeckIds
            .where(
              (deckId) =>
                  speciesIdsByDeckId[deckId]?.contains(speciesId) ?? false,
            )
            .toList(growable: false);
        if (deckIds.isEmpty) {
          continue;
        }
        final existingRow = existingBySpeciesId[speciesId];
        final existingOwnerDeckId = existingRow?['owner_deck_id'] as String?;
        final ownerDeckId = deckIds.contains(existingOwnerDeckId)
            ? existingOwnerDeckId!
            : deckIds.first;
        assignments.putIfAbsent(ownerDeckId, () => <String>[]).add(speciesId);

        final alreadyWantsInatPhotos =
            (existingRow?['wants_inat_photos'] as int? ?? 0) == 1;
        final alreadyWantsCommonNames =
            (existingRow?['wants_common_names'] as int? ?? 0) == 1;
        final wantsInatPhotos =
            alreadyWantsInatPhotos ||
            deckIds.any((deckId) => includeInatPhotosByDeckId[deckId] ?? true);
        final wantsCommonNames =
            alreadyWantsCommonNames ||
            deckIds.any((deckId) => includeCommonNamesByDeckId[deckId] ?? true);

        await _upsertSpeciesWorkAndCapabilities(
          txn,
          speciesId,
          ownerDeckId: ownerDeckId,
          deckIds: deckIds,
          wantsInatPhotos: wantsInatPhotos,
          wantsCommonNames: wantsCommonNames,
          now: now,
        );
      }

      // Drop stale rows for species that are no longer part of the active plan.
      final activeSpeciesIds = allSpeciesIds.toSet();
      for (final row in existingRows) {
        final speciesId = row['species_id'] as String;
        if (activeSpeciesIds.contains(speciesId)) {
          continue;
        }
        final deckIds = existingDeckIdsBySpecies[speciesId] ?? const [];
        final hasTrackedDeck = deckIds.any(deckPriority.containsKey);
        if (!hasTrackedDeck) {
          continue;
        }
        await txn.delete(
          speciesWorkTable,
          where: 'species_id = ?',
          whereArgs: [speciesId],
        );
        await txn.delete(
          deckMembershipTable,
          where: 'species_id = ?',
          whereArgs: [speciesId],
        );
      }

      return assignments.map(
        (deckId, speciesIds) =>
            MapEntry(deckId, List<String>.unmodifiable(speciesIds)),
      );
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
        speciesWorkTable,
        where: 'species_id = ?',
        whereArgs: [speciesId],
      );
      final existingRow = existingRows.isEmpty ? null : existingRows.single;
      final existingMembershipRows = await txn.query(
        deckMembershipTable,
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
    await txn.insert(speciesWorkTable, {
      'species_id': speciesId,
      'owner_deck_id': ownerDeckId,
      'deck_count': deckIds.length,
      'wants_inat_photos': wantsInatPhotos ? 1 : 0,
      'wants_common_names': wantsCommonNames ? 1 : 0,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    for (final deckId in deckIds) {
      await txn.insert(deckMembershipTable, {
        'species_id': speciesId,
        'deck_id': deckId,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    await txn.insert(capabilityStateTable, {
      'species_id': speciesId,
      'capability': _capabilityName(EnrichmentStage.base),
      'state': _capabilityStatePending,
      'priority_tier': 0,
      'attempt_count': 0,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    if (wantsCommonNames) {
      await txn.insert(capabilityStateTable, {
        'species_id': speciesId,
        'capability': _capabilityName(EnrichmentStage.names),
        'state': _capabilityStatePending,
        'priority_tier': 20,
        'attempt_count': 0,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    if (wantsInatPhotos) {
      await _catchUpInatFallback(txn, speciesId, now);
    }
  }

  /// Consent can arrive after `base` already resolved without an image: the
  /// deck-import flow schedules once with consent withheld (to start `base`
  /// downloads immediately, before the user has even seen the import
  /// dialog) and again with the user's actual choice once they dismiss it.
  /// `BaseWorker`'s own reactive inatPrimary/inatBackfill seed only fires
  /// once, exactly when it marks `base` terminal — a species whose `base`
  /// resolved (`noResult`/`permanentFailure`) before consent arrived would
  /// otherwise never get an inatPrimary row at all, since the `base` insert
  /// above is `ConflictAlgorithm.ignore` and nothing else revisits an
  /// already-terminal species. Catches that case up here, the other place
  /// `wants_inat_photos` can flip from false to true.
  Future<void> _catchUpInatFallback(
    DatabaseExecutor txn,
    String speciesId,
    int now,
  ) async {
    final baseRows = await txn.query(
      capabilityStateTable,
      columns: const ['state'],
      where: 'species_id = ? AND capability = ?',
      whereArgs: [speciesId, _capabilityName(EnrichmentStage.base)],
      limit: 1,
    );
    if (baseRows.isEmpty) return;
    final baseState = baseRows.single['state'] as String?;
    if (baseState == null ||
        baseState == 'done' ||
        !_capabilityStateTerminal.contains(baseState)) {
      return;
    }
    await txn.insert(capabilityStateTable, {
      'species_id': speciesId,
      'capability': _capabilityName(EnrichmentStage.inatPrimary),
      'state': _capabilityStatePending,
      'priority_tier': 10,
      'attempt_count': 0,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await txn.insert(capabilityStateTable, {
      'species_id': speciesId,
      'capability': _capabilityName(EnrichmentStage.inatBackfill),
      'state': _capabilityStatePending,
      'priority_tier': 40,
      'attempt_count': 0,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// Registers [items] against [taxonomyWorkTable], keyed by
  /// `runtime_entity_key` so multiple calls for the same taxon (from
  /// different species/decks) merge into one row instead of duplicating it.
  /// Each item's species are added to [taxonomyWorkSpeciesTable] via
  /// `INSERT OR IGNORE`, so membership unions automatically across calls
  /// without a read-merge. No deck is tracked: deck scoping is derived from
  /// the species junction joined against [deckMembershipTable].
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
        taxonomyWorkTable,
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
        await txn.insert(taxonomyWorkTable, {
          'work_key': workKey,
          'runtime_entity_key': item.runtimeEntityKey,
          'common_names_state': existingRow?['common_names_state'] ?? 'pending',
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        for (final speciesId in item.speciesIds) {
          await txn.insert(taxonomyWorkSpeciesTable, {
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
        deckMembershipTable,
        columns: const ['species_id'],
        where: 'deck_id = ?',
        whereArgs: [normalizedDeckId],
      );
      final affectedSpeciesIds = {
        for (final row in membershipRows) row['species_id'] as String,
      };
      await txn.delete(
        deckMembershipTable,
        where: 'deck_id = ?',
        whereArgs: [normalizedDeckId],
      );

      for (final speciesId in affectedSpeciesIds) {
        final speciesRows = await txn.query(
          speciesWorkTable,
          where: 'species_id = ?',
          whereArgs: [speciesId],
        );
        if (speciesRows.isEmpty) continue;
        final ownerDeckId = speciesRows.single['owner_deck_id'] as String?;
        final remainingMembership = await txn.query(
          deckMembershipTable,
          columns: const ['deck_id'],
          where: 'species_id = ?',
          whereArgs: [speciesId],
        );
        if (remainingMembership.isEmpty) {
          // No deck references this species anymore (the departing deck's
          // own membership rows were already deleted above) — nothing left
          // to track.
          await txn.delete(
            speciesWorkTable,
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
          speciesWorkTable,
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
        unresolvedNamesTable,
        where: 'deck_id = ?',
        whereArgs: [normalizedDeckId],
      );
    });
  }

  /// Idempotently ensures a `pending` queue row exists for [speciesId]/
  /// [capability] at [priorityTier]. A no-op if that (species, capability)
  /// row already exists (regardless of its current state) — this is how
  /// `inatPrimary`/`inatBackfill` get seeded reactively (e.g. by `BaseWorker`
  /// on a download failure) instead of upfront for every species.
  ///
  /// For the two iNat-photo capabilities (`inatPrimary`/`inatBackfill`),
  /// also a no-op if the species hasn't (yet) been granted
  /// `wants_inat_photos` consent — mirrors `_upsertSpeciesWorkAndCapabilities`
  /// only ever seeding `speciesCommonNames` up front when `wantsCommonNames`
  /// is true. Without this, a species belonging only to a deck that declined
  /// iNat photos would still get an iNat photo fetched the moment its
  /// reference-image download failed or was absent (`BaseWorker`'s
  /// fallback), since consent was never checked before reactively seeding
  /// these rows.
  Future<void> seedCapability(
    String speciesId,
    EnrichmentStage capability, {
    required int priorityTier,
  }) async {
    final capabilityName = _capabilityName(capability);
    final db = await _db;
    if (capabilityName == 'inatPrimary' || capabilityName == 'inatBackfill') {
      final speciesRows = await db.query(
        speciesWorkTable,
        columns: const ['wants_inat_photos'],
        where: 'species_id = ?',
        whereArgs: [speciesId],
        limit: 1,
      );
      final wantsInatPhotos =
          speciesRows.isNotEmpty &&
          (speciesRows.single['wants_inat_photos'] as int? ?? 0) == 1;
      if (!wantsInatPhotos) return;
    }
    await db.insert(capabilityStateTable, {
      'species_id': speciesId,
      'capability': capabilityName,
      'state': _capabilityStatePending,
      'priority_tier': priorityTier,
      'attempt_count': 0,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// Marks [speciesId]/[capability] terminal — [state] must be `'done'` or
  /// `'noResult'` (the two non-failure terminal outcomes from issue #57's
  /// state vocabulary; permanent failure goes through
  /// [recordCapabilityAttemptFailure] instead, since that path needs the
  /// attempt-count bookkeeping).
  Future<void> markCapabilityTerminal(
    String speciesId,
    EnrichmentStage capability,
    String state,
  ) {
    return _markTerminal(
      table: capabilityStateTable,
      stateColumn: 'state',
      whereClause: 'species_id = ? AND capability = ?',
      whereArgs: [speciesId, _capabilityName(capability)],
      state: state,
    );
  }

  /// Records a failed attempt at [speciesId]/[capability]. Schedules a retry
  /// with escalating backoff (picked from [backoffSteps] by attempt count,
  /// clamped to the last step) unless [maxAttempts] has been reached, in
  /// which case the row becomes `permanentFailure`. Returns whether this call
  /// just gave up, so the caller knows whether to trigger a reactive
  /// fallback (e.g. `BaseWorker` falling back to `inatPrimary`).
  Future<bool> recordCapabilityAttemptFailure(
    String speciesId,
    EnrichmentStage capability, {
    required int maxAttempts,
    required List<Duration> backoffSteps,
    String? error,
    String? failureKind,
  }) {
    return _recordAttemptFailure(
      table: capabilityStateTable,
      stateColumn: 'state',
      whereClause: 'species_id = ? AND capability = ?',
      whereArgs: [speciesId, _capabilityName(capability)],
      maxAttempts: maxAttempts,
      backoffSteps: backoffSteps,
      error: error,
      failureKind: failureKind,
    );
  }

  /// Marks [workKey]'s taxonomy common-names capability terminal — [state]
  /// must be `'done'` or `'noResult'` (the two non-failure terminal outcomes;
  /// permanent failure goes through [recordTaxonomyCapabilityAttemptFailure]
  /// instead, since that path needs the attempt-count bookkeeping).
  Future<void> markTaxonomyCapabilityTerminal(String workKey, String state) {
    return _markTerminal(
      table: taxonomyWorkTable,
      stateColumn: 'common_names_state',
      whereClause: 'work_key = ?',
      whereArgs: [workKey],
      state: state,
    );
  }

  /// Same retry/give-up bookkeeping as [recordCapabilityAttemptFailure], but
  /// for a taxonomy work item (keyed by `work_key` on [taxonomyWorkTable]
  /// instead of `(species_id, capability)` on [capabilityStateTable]).
  Future<bool> recordTaxonomyCapabilityAttemptFailure(
    String workKey, {
    required int maxAttempts,
    required List<Duration> backoffSteps,
    String? error,
    String? failureKind,
  }) {
    return _recordAttemptFailure(
      table: taxonomyWorkTable,
      stateColumn: 'common_names_state',
      whereClause: 'work_key = ?',
      whereArgs: [workKey],
      maxAttempts: maxAttempts,
      backoffSteps: backoffSteps,
      error: error,
      failureKind: failureKind,
    );
  }

  /// Seeds `pending` rows in [unresolvedNamesTable] for scientific names that
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
          unresolvedNamesTable,
          where: 'deck_id = ? AND name = ?',
          whereArgs: [deckId, name],
        );
        final existingRow = existing.isEmpty ? null : existing.first;
        final alreadyWantsInatPhotos =
            (existingRow?['wants_inat_photos'] as int? ?? 0) == 1;
        final alreadyWantsCommonNames =
            (existingRow?['wants_common_names'] as int? ?? 0) == 1;
        await txn.insert(unresolvedNamesTable, {
          'deck_id': deckId,
          'name': name,
          'state': existingRow?['state'] ?? _capabilityStatePending,
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

  /// Every species set currently tracked in [deckMembershipTable], keyed by
  /// deck id. Used when scheduling new decks so their species-owner
  /// assignment call ([assignSpeciesOwners]) can include already-tracked
  /// decks as lower-priority input — without this, a species already owned
  /// by a still-in-flight deck could get silently reassigned to a new deck
  /// that merely happens to share it.
  Future<Map<String, Set<String>>> loadAllDeckSpeciesSnapshots() async {
    final db = await _db;
    final rows = await db.query(deckMembershipTable);
    final result = <String, Set<String>>{};
    for (final row in rows) {
      final deckId = row['deck_id'] as String;
      final speciesId = row['species_id'] as String;
      result.putIfAbsent(deckId, () => <String>{}).add(speciesId);
    }
    return result;
  }

  /// Removes a successfully-resolved (or permanently abandoned) unresolved
  /// name — there's nothing left to track once either happens.
  Future<void> deleteUnresolvedName(String deckId, String name) async {
    final db = await _db;
    await db.delete(
      unresolvedNamesTable,
      where: 'deck_id = ? AND name = ?',
      whereArgs: [deckId, name],
    );
  }

  /// Same retry/give-up bookkeeping as [recordCapabilityAttemptFailure], but
  /// for an unresolved-name item (keyed by `(deck_id, name)` on
  /// [unresolvedNamesTable]). Unlike the other queue tables, giving up here
  /// does not delete the row — it stays `permanentFailure` so it isn't
  /// silently retried again, and so `UnresolvedNamesObserverPort` only needs
  /// to fire once. This table has no `last_failure_kind` column (unresolved
  /// names don't need the same temporary/permanent classification the
  /// capability tables do), so that part of the shared bookkeeping is
  /// skipped here.
  Future<bool> recordUnresolvedNameAttemptFailure(
    String deckId,
    String name, {
    required int maxAttempts,
    required List<Duration> backoffSteps,
    String? error,
  }) {
    return _recordAttemptFailure(
      table: unresolvedNamesTable,
      stateColumn: 'state',
      whereClause: 'deck_id = ? AND name = ?',
      whereArgs: [deckId, name],
      maxAttempts: maxAttempts,
      backoffSteps: backoffSteps,
      error: error,
      hasFailureKindColumn: false,
    );
  }

  /// Shared implementation behind [markCapabilityTerminal] and
  /// [markTaxonomyCapabilityTerminal] — same reset-and-set logic, different
  /// table/state-column/key shape.
  Future<void> _markTerminal({
    required String table,
    required String stateColumn,
    required String whereClause,
    required List<Object?> whereArgs,
    required String state,
  }) async {
    final db = await _db;
    await db.update(
      table,
      {
        stateColumn: state,
        'attempt_count': 0,
        'next_attempt_at': null,
        'last_error': null,
        'last_failure_kind': null,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: whereClause,
      whereArgs: whereArgs,
    );
  }

  /// Shared implementation behind [recordCapabilityAttemptFailure],
  /// [recordTaxonomyCapabilityAttemptFailure], and
  /// [recordUnresolvedNameAttemptFailure] — same escalating-backoff/give-up
  /// policy, different table/state-column/key shape. [hasFailureKindColumn]
  /// is false for [unresolvedNamesTable], which has no `last_failure_kind`
  /// column.
  Future<bool> _recordAttemptFailure({
    required String table,
    required String stateColumn,
    required String whereClause,
    required List<Object?> whereArgs,
    required int maxAttempts,
    required List<Duration> backoffSteps,
    String? error,
    String? failureKind,
    bool hasFailureKindColumn = true,
  }) async {
    final db = await _db;
    final rows = await db.query(
      table,
      columns: const ['attempt_count'],
      where: whereClause,
      whereArgs: whereArgs,
    );
    final currentAttempts = rows.isEmpty
        ? 0
        : (rows.single['attempt_count'] as int? ?? 0);
    final nextAttempts = currentAttempts + 1;
    final now = DateTime.now();
    final gaveUp = nextAttempts >= maxAttempts;
    final backoffIndex = (nextAttempts - 1).clamp(0, backoffSteps.length - 1);
    final values = <String, Object?>{
      stateColumn: gaveUp ? 'permanentFailure' : _capabilityStateRetryScheduled,
      'attempt_count': nextAttempts,
      'next_attempt_at': gaveUp
          ? null
          : now.add(backoffSteps[backoffIndex]).millisecondsSinceEpoch,
      'last_error': error,
      'updated_at': now.millisecondsSinceEpoch,
    };
    if (hasFailureKindColumn) {
      values['last_failure_kind'] = failureKind;
    }
    await db.update(table, values, where: whereClause, whereArgs: whereArgs);
    return gaveUp;
  }

  /// Claims up to [limit] species needing `base` work (reference-image
  /// download), atomically flipping them to `running` so a concurrent call
  /// (there should only ever be one `BaseWorker`, but this keeps the
  /// contract honest) can't claim the same species twice.
  ///
  /// Requires an existing [deckMembershipTable] row — a species can be
  /// seeded here and then have every deck referencing it deleted before this
  /// ever gets claimed (`releaseDeck` deliberately leaves this permanent
  /// dedup-cache row behind); without this check that claim would still go
  /// ahead and burn a real reference-image download for a species nobody
  /// wants anymore.
  Future<List<String>> claimBaseWorkBatch({required int limit}) async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.transaction((txn) async {
      final rows = await txn.rawQuery(
        '''
        SELECT c.species_id AS species_id
          FROM $capabilityStateTable c
         WHERE c.capability = 'base'
           AND c.state IN (?, ?)
           AND (c.next_attempt_at IS NULL OR c.next_attempt_at <= ?)
           AND EXISTS (
             SELECT 1 FROM $deckMembershipTable m
              WHERE m.species_id = c.species_id
           )
         ORDER BY c.updated_at ASC
         LIMIT ?
        ''',
        [_capabilityStatePending, _capabilityStateRetryScheduled, now, limit],
      );
      final speciesIds = rows
          .map((row) => row['species_id'] as String)
          .toList(growable: false);
      if (speciesIds.isEmpty) return const <String>[];
      await txn.update(
        capabilityStateTable,
        {'state': 'running', 'updated_at': now},
        where:
            "capability = 'base' AND species_id IN "
            '(${List.filled(speciesIds.length, '?').join(', ')})',
        whereArgs: speciesIds,
      );
      return speciesIds;
    });
  }

  /// Claims the single highest-priority pending item across
  /// `inatPrimary`/`speciesCommonNames`/`inatBackfill` (from
  /// [capabilityStateTable]), `taxonomyCommonNames` (from [taxonomyWorkTable])
  /// and `nameResolution` (from [unresolvedNamesTable]) — the shared queue a
  /// single rate-limited `INatWorker` drains. Lower `priority_tier` wins
  /// (species rows carry their own; taxonomy is always 30, name resolution
  /// always 50). Returns `null` when nothing is claimable.
  ///
  /// Runs one query per table rather than a single `UNION ALL`, since each
  /// table needs different columns back (taxonomy needs `runtime_entity_key`
  /// and `species_ids_json` too, not just its key) — three small queries in
  /// one transaction over these tiny tables is simpler than reshaping every
  /// row into a common column set.
  ///
  /// The species query requires an existing [deckMembershipTable] row for
  /// the same reason [claimBaseWorkBatch] does — a species can outlive every
  /// deck that referenced it (its permanent dedup-cache row is deliberately
  /// left behind by `releaseDeck`) before a reactively-seeded item like
  /// `inatBackfill` ever gets claimed; without this check, that claim would
  /// still burn a real, rate-limited iNaturalist request for nothing.
  Future<INatWorkItem?> claimNextINatWorkItem() async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.transaction((txn) async {
      final speciesRows = await txn.rawQuery(
        '''
        SELECT c.species_id AS species_id, c.capability AS capability,
               c.priority_tier AS priority_tier
          FROM $capabilityStateTable c
         WHERE c.capability IN ('inatPrimary', 'speciesCommonNames', 'inatBackfill')
           AND c.state IN (?, ?)
           AND (c.next_attempt_at IS NULL OR c.next_attempt_at <= ?)
           AND EXISTS (
             SELECT 1 FROM $deckMembershipTable m
              WHERE m.species_id = c.species_id
           )
         ORDER BY c.priority_tier ASC, c.updated_at ASC
         LIMIT 1
        ''',
        [_capabilityStatePending, _capabilityStateRetryScheduled, now],
      );
      // Guard like the species claim: only claim a taxonomy row if at least
      // one of its species still has a deck-membership row, so an orphaned
      // taxon (every referencing deck deleted) never burns an iNat request.
      final taxonomyRows = await txn.rawQuery(
        '''
        SELECT t.work_key AS work_key,
               t.runtime_entity_key AS runtime_entity_key
          FROM $taxonomyWorkTable t
         WHERE t.common_names_state IN (?, ?)
           AND (t.next_attempt_at IS NULL OR t.next_attempt_at <= ?)
           AND EXISTS (
             SELECT 1 FROM $taxonomyWorkSpeciesTable ts
             JOIN $deckMembershipTable m ON m.species_id = ts.species_id
              WHERE ts.work_key = t.work_key
           )
         ORDER BY t.updated_at ASC
         LIMIT 1
        ''',
        [_capabilityStatePending, _capabilityStateRetryScheduled, now],
      );
      final unresolvedRows = await txn.query(
        unresolvedNamesTable,
        where:
            'state IN (?, ?) AND (next_attempt_at IS NULL OR next_attempt_at <= ?)',
        whereArgs: [
          _capabilityStatePending,
          _capabilityStateRetryScheduled,
          now,
        ],
        orderBy: 'updated_at ASC',
        limit: 1,
      );

      final candidates = <(int priorityTier, String source)>[
        if (speciesRows.isNotEmpty)
          (speciesRows.single['priority_tier'] as int, 'species'),
        if (taxonomyRows.isNotEmpty) (30, 'taxonomy'),
        if (unresolvedRows.isNotEmpty) (50, 'unresolvedName'),
      ];
      if (candidates.isEmpty) return null;
      candidates.sort((a, b) => a.$1.compareTo(b.$1));

      switch (candidates.first.$2) {
        case 'species':
          final row = speciesRows.single;
          final speciesId = row['species_id'] as String;
          final capability = row['capability'] as String;
          await txn.update(
            capabilityStateTable,
            {'state': 'running', 'updated_at': now},
            where: 'species_id = ? AND capability = ?',
            whereArgs: [speciesId, capability],
          );
          return INatWorkItem.species(
            _workItemKindForCapabilityName(capability),
            speciesId,
            priorityTier: row['priority_tier'] as int,
          );
        case 'taxonomy':
          final row = taxonomyRows.single;
          final workKey = row['work_key'] as String;
          await txn.update(
            taxonomyWorkTable,
            {'common_names_state': 'running', 'updated_at': now},
            where: 'work_key = ?',
            whereArgs: [workKey],
          );
          final taxonomySpeciesRows = await txn.query(
            taxonomyWorkSpeciesTable,
            columns: const ['species_id'],
            where: 'work_key = ?',
            whereArgs: [workKey],
          );
          return INatWorkItem.taxonomy(
            workKey,
            row['runtime_entity_key'] as String,
            {
              for (final r in taxonomySpeciesRows) r['species_id'] as String,
            },
          );
        case 'unresolvedName':
          final row = unresolvedRows.single;
          final deckId = row['deck_id'] as String;
          final name = row['name'] as String;
          await txn.update(
            unresolvedNamesTable,
            {'state': 'running', 'updated_at': now},
            where: 'deck_id = ? AND name = ?',
            whereArgs: [deckId, name],
          );
          return INatWorkItem.nameResolution(
            deckId,
            name,
            wantsInatPhotos: (row['wants_inat_photos'] as int? ?? 1) == 1,
            wantsCommonNames: (row['wants_common_names'] as int? ?? 1) == 1,
          );
        default:
          return null;
      }
    });
  }

  /// Clears `next_attempt_at` on every `retryScheduled` row across the three
  /// queue tables, so they become immediately claimable again — mirrors
  /// `EnrichmentJobRepository.clearRetryAttemptForRetryScheduledJobs`. Called
  /// once a `HostCooldownTracker` cooldown clears.
  Future<int> clearRetryAttemptForRetryScheduledWorkItems() async {
    final db = await _db;
    var count = 0;
    count += await db.update(
      capabilityStateTable,
      {'next_attempt_at': null},
      where: 'state = ? AND next_attempt_at IS NOT NULL',
      whereArgs: [_capabilityStateRetryScheduled],
    );
    count += await db.update(
      taxonomyWorkTable,
      {'next_attempt_at': null},
      where: 'common_names_state = ? AND next_attempt_at IS NOT NULL',
      whereArgs: [_capabilityStateRetryScheduled],
    );
    count += await db.update(
      unresolvedNamesTable,
      {'next_attempt_at': null},
      where: 'state = ? AND next_attempt_at IS NOT NULL',
      whereArgs: [_capabilityStateRetryScheduled],
    );
    return count;
  }

  /// Live counts of species-capability work items grouped by capability and
  /// state — used by the diagnostics page to show what's still outstanding
  /// without reconstructing it from an event log.
  Future<List<EnrichmentWorkStateCount>> loadCapabilityStateCounts() async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT capability, state, COUNT(*) as count, '
      'MIN(next_attempt_at) as next_attempt_at FROM $capabilityStateTable '
      'GROUP BY capability, state',
    );
    return rows
        .map(
          (row) => EnrichmentWorkStateCount(
            label: row['capability'] as String,
            state: row['state'] as String,
            count: row['count'] as int,
            nextAttemptAt: _millisToDateTime(row['next_attempt_at'] as int?),
          ),
        )
        .toList(growable: false);
  }

  /// Live counts of taxonomy common-name work items grouped by state.
  Future<List<EnrichmentWorkStateCount>> loadTaxonomyWorkStateCounts() async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT common_names_state as state, COUNT(*) as count, '
      'MIN(next_attempt_at) as next_attempt_at '
      'FROM $taxonomyWorkTable GROUP BY common_names_state',
    );
    return rows
        .map(
          (row) => EnrichmentWorkStateCount(
            label: 'taxonomyCommonNames',
            state: row['state'] as String,
            count: row['count'] as int,
            nextAttemptAt: _millisToDateTime(row['next_attempt_at'] as int?),
          ),
        )
        .toList(growable: false);
  }

  /// Live counts of species stuck in [unresolvedNamesTable] (no taxonomy
  /// match yet) grouped by state.
  Future<List<EnrichmentWorkStateCount>> loadUnresolvedNamesStateCounts() async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT state, COUNT(*) as count, MIN(next_attempt_at) as next_attempt_at '
      'FROM $unresolvedNamesTable GROUP BY state',
    );
    return rows
        .map(
          (row) => EnrichmentWorkStateCount(
            label: 'unresolvedNames',
            state: row['state'] as String,
            count: row['count'] as int,
            nextAttemptAt: _millisToDateTime(row['next_attempt_at'] as int?),
          ),
        )
        .toList(growable: false);
  }

  static DateTime? _millisToDateTime(int? millis) {
    if (millis == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  /// Startup crash recovery: any row left `running` (the process died
  /// mid-claim, e.g. app kill) reverts to `pending` so it gets reclaimed.
  /// Safe to call unconditionally on every app start — a no-op when nothing
  /// was interrupted. There is exactly one `BaseWorker`/`INatWorker` per
  /// process in this app, so — unlike `EnrichmentJobRepository`'s job
  /// leases — no owner/lease arbitration is needed here, just a blanket reset.
  Future<void> recoverInterruptedWork() async {
    final db = await _db;
    await db.update(
      capabilityStateTable,
      {'state': _capabilityStatePending},
      where: 'state = ?',
      whereArgs: ['running'],
    );
    await db.update(
      taxonomyWorkTable,
      {'common_names_state': _capabilityStatePending},
      where: 'common_names_state = ?',
      whereArgs: ['running'],
    );
    await db.update(
      unresolvedNamesTable,
      {'state': _capabilityStatePending},
      where: 'state = ?',
      whereArgs: ['running'],
    );
  }

  /// Builds [DeckEnrichmentProjection] for [deckId] from every species
  /// currently in [deckMembershipTable] for it (regardless of which deck
  /// "owns" a given shared species) joined against
  /// [capabilityStateTable], plus taxonomy items from [taxonomyWorkTable]
  /// whose `deck_ids_json` references this deck.
  Future<DeckEnrichmentProjection> loadDeckProjection(String deckId) async {
    final db = await _db;
    final rows = await db.rawQuery(
      '''
      SELECT m.species_id AS species_id, c.capability AS capability,
             c.state AS state, c.next_attempt_at AS next_attempt_at,
             w.wants_inat_photos AS wants_inat_photos,
             w.wants_common_names AS wants_common_names
        FROM $deckMembershipTable m
        LEFT JOIN $capabilityStateTable c ON c.species_id = m.species_id
        LEFT JOIN $speciesWorkTable w ON w.species_id = m.species_id
       WHERE m.deck_id = ?
      ''',
      [deckId],
    );

    final statesBySpecies = <String, Map<String, String>>{};
    final consentBySpecies =
        <String, ({bool wantsInatPhotos, bool wantsCommonNames})>{};
    var immediatePending = false;
    DateTime? earliestRetryAt;
    void considerState(String? state, Object? nextAttemptAtMillis) {
      if (state == 'pending' || state == 'running') {
        immediatePending = true;
      }
      if (state != 'retryScheduled' || nextAttemptAtMillis is! int) return;
      final candidate = DateTime.fromMillisecondsSinceEpoch(
        nextAttemptAtMillis,
      );
      if (earliestRetryAt == null || candidate.isBefore(earliestRetryAt!)) {
        earliestRetryAt = candidate;
      }
    }

    for (final row in rows) {
      final speciesId = row['species_id'] as String;
      final capability = row['capability'] as String?;
      final state = row['state'] as String?;
      final states = statesBySpecies.putIfAbsent(speciesId, () => {});
      if (capability != null && state != null) {
        states[capability] = state;
      }
      consentBySpecies[speciesId] = (
        wantsInatPhotos: (row['wants_inat_photos'] as int? ?? 0) == 1,
        wantsCommonNames: (row['wants_common_names'] as int? ?? 0) == 1,
      );
      considerState(state, row['next_attempt_at']);
    }

    var imageCompleteCount = 0;
    var imageDoneCount = 0;
    var commonNamesWanted = 0;
    var commonNamesTerminal = 0;
    var backfillWanted = 0;
    var backfillTerminal = 0;
    var anyPermanentFailure = false;
    var anyImagePermanentFailure = false;
    var wantsInatPhotosCount = 0;
    var wantsCommonNamesCount = 0;

    for (final entry in statesBySpecies.entries) {
      final states = entry.value;
      final baseState = states['base'];
      final primaryState = states['inatPrimary'];

      // A species is image-complete once `base` is terminal AND — only if
      // base didn't itself succeed — `inatPrimary` (seeded reactively by
      // BaseWorker exactly when base doesn't succeed) is also terminal. A
      // species whose base succeeded never gets an inatPrimary row at all,
      // so "no row" must count as complete, not incomplete, in that case.
      // Likewise, a species without iNat-photo consent never gets an
      // inatPrimary row either (seedCapability no-ops for it) — without this
      // branch, such a species' image stage would never resolve and the
      // whole deck would stay in loadingBase forever, waiting on a request
      // that will never be made.
      if (_capabilityStateTerminal.contains(baseState)) {
        final wantsInatPhotos =
            consentBySpecies[entry.key]?.wantsInatPhotos ?? false;
        if (baseState == 'done') {
          imageCompleteCount++;
        } else if (_capabilityStateTerminal.contains(primaryState) ||
            !wantsInatPhotos) {
          imageCompleteCount++;
        }
      }
      if (baseState == 'done' || primaryState == 'done') {
        imageDoneCount++;
      }
      if (baseState == 'permanentFailure' ||
          primaryState == 'permanentFailure') {
        anyImagePermanentFailure = true;
      }

      if (states.containsKey('speciesCommonNames')) {
        commonNamesWanted++;
        if (_capabilityStateTerminal.contains(states['speciesCommonNames'])) {
          commonNamesTerminal++;
        }
      }
      if (states.containsKey('inatBackfill')) {
        backfillWanted++;
        if (_capabilityStateTerminal.contains(states['inatBackfill'])) {
          backfillTerminal++;
        }
      }
      if (states.values.contains('permanentFailure')) {
        anyPermanentFailure = true;
      }

      final consent = consentBySpecies[entry.key];
      if (consent?.wantsInatPhotos ?? false) wantsInatPhotosCount++;
      if (consent?.wantsCommonNames ?? false) wantsCommonNamesCount++;
    }

    // Taxa referenced by this deck = taxa whose species are members of it.
    // DISTINCT collapses a taxon shared by several of the deck's species into
    // one row (state/next_attempt_at are functionally determined by work_key).
    final taxonomyRows = await db.rawQuery(
      '''
      SELECT DISTINCT t.work_key AS work_key,
             t.common_names_state AS common_names_state,
             t.next_attempt_at AS next_attempt_at
        FROM $taxonomyWorkTable t
        JOIN $taxonomyWorkSpeciesTable ts ON ts.work_key = t.work_key
        JOIN $deckMembershipTable m ON m.species_id = ts.species_id
       WHERE m.deck_id = ?
      ''',
      [deckId],
    );
    var taxonomyTotal = 0;
    var taxonomyTerminal = 0;
    for (final row in taxonomyRows) {
      taxonomyTotal++;
      final state = row['common_names_state'] as String?;
      if (_capabilityStateTerminal.contains(state)) {
        taxonomyTerminal++;
      }
      if (state == 'permanentFailure') {
        anyPermanentFailure = true;
      }
      considerState(state, row['next_attempt_at']);
    }

    final unresolvedNameRows = await db.query(
      unresolvedNamesTable,
      where: 'deck_id = ?',
      whereArgs: [deckId],
    );
    var pendingUnresolvedNameCount = 0;
    for (final row in unresolvedNameRows) {
      final state = row['state'] as String?;
      if (state == 'permanentFailure') {
        anyPermanentFailure = true;
      } else {
        pendingUnresolvedNameCount++;
      }
      considerState(state, row['next_attempt_at']);
    }

    return DeckEnrichmentProjection(
      deckId: deckId,
      speciesCount: statesBySpecies.length,
      imageCompleteSpeciesCount: imageCompleteCount,
      imageDoneSpeciesCount: imageDoneCount,
      speciesCommonNamesWantedCount: commonNamesWanted,
      speciesCommonNamesTerminalCount: commonNamesTerminal,
      inatBackfillWantedCount: backfillWanted,
      inatBackfillTerminalCount: backfillTerminal,
      taxonomyTotalCount: taxonomyTotal,
      taxonomyTerminalCount: taxonomyTerminal,
      pendingUnresolvedNameCount: pendingUnresolvedNameCount,
      wantsInatPhotosSpeciesCount: wantsInatPhotosCount,
      wantsCommonNamesSpeciesCount: wantsCommonNamesCount,
      anyPermanentFailure: anyPermanentFailure,
      anyImagePermanentFailure: anyImagePermanentFailure,
      hasImmediatePendingWork: immediatePending,
      earliestRetryAt: earliestRetryAt,
    );
  }

  /// Returns every deck id whose enrichment state changed at or after
  /// [sinceMillis] (epoch milliseconds), across all three queue tables —
  /// the cheap "what changed" query a poller uses to only recompute
  /// [loadDeckProjection] for decks that actually moved, the same way
  /// `EnrichmentJobRepository.loadJobsUpdatedSince`'s delta-loading avoids
  /// reprocessing decks that haven't changed.
  ///
  /// Deliberately `>=`, not `>`: [sinceMillis] is captured (by the caller)
  /// before the query runs, and timestamps here have millisecond resolution
  /// — a write landing in that same millisecond would compare equal, and a
  /// strict `>` would exclude it from this poll *and* every future one
  /// (the cursor never moves backward), silently freezing that deck's state
  /// forever. Matches `EnrichmentJobRepository.loadJobsUpdatedSince`, which
  /// uses `>=` for the same reason.
  Future<Set<String>> loadDeckIdsUpdatedSince(int sinceMillis) async {
    final db = await _db;
    final deckIds = <String>{};

    final capabilityRows = await db.rawQuery(
      '''
      SELECT DISTINCT m.deck_id AS deck_id
        FROM $capabilityStateTable c
        JOIN $deckMembershipTable m ON m.species_id = c.species_id
       WHERE c.updated_at >= ?
      ''',
      [sinceMillis],
    );
    for (final row in capabilityRows) {
      deckIds.add(row['deck_id'] as String);
    }

    final taxonomyRows = await db.rawQuery(
      '''
      SELECT DISTINCT m.deck_id AS deck_id
        FROM $taxonomyWorkTable t
        JOIN $taxonomyWorkSpeciesTable ts ON ts.work_key = t.work_key
        JOIN $deckMembershipTable m ON m.species_id = ts.species_id
       WHERE t.updated_at >= ?
      ''',
      [sinceMillis],
    );
    for (final row in taxonomyRows) {
      deckIds.add(row['deck_id'] as String);
    }

    final unresolvedRows = await db.query(
      unresolvedNamesTable,
      columns: const ['deck_id'],
      where: 'updated_at >= ?',
      whereArgs: [sinceMillis],
    );
    for (final row in unresolvedRows) {
      deckIds.add(row['deck_id'] as String);
    }

    return deckIds;
  }

  /// Whether any species/taxonomy/unresolved-name work anywhere is still
  /// non-terminal — the aggregate counterpart to
  /// `EnrichmentJobRepository.hasPendingWork` used to decide whether the
  /// background keepalive service needs to stay up.
  Future<bool> hasPendingWork() async {
    final db = await _db;
    final terminalStates = _capabilityStateTerminal.toList(growable: false);
    final capabilityRows = await db.query(
      capabilityStateTable,
      columns: const ['species_id'],
      where: 'state NOT IN (?, ?, ?)',
      whereArgs: terminalStates,
      limit: 1,
    );
    if (capabilityRows.isNotEmpty) return true;

    final taxonomyRows = await db.query(
      taxonomyWorkTable,
      columns: const ['work_key'],
      where: 'common_names_state NOT IN (?, ?, ?)',
      whereArgs: terminalStates,
      limit: 1,
    );
    if (taxonomyRows.isNotEmpty) return true;

    final unresolvedRows = await db.query(
      unresolvedNamesTable,
      columns: const ['name'],
      where: 'state != ?',
      whereArgs: const ['permanentFailure'],
      limit: 1,
    );
    return unresolvedRows.isNotEmpty;
  }

  /// Species referencing [deckId] whose image stages are terminal but
  /// neither `base` nor `inatPrimary` ever reached `done` — i.e. every
  /// avenue for an image was exhausted (reference DB and iNaturalist alike)
  /// without one landing locally. A diagnostic list, not used for progress —
  /// these species are still counted as "image-complete" (nothing left to
  /// wait for), just without an actual picture.
  Future<Set<String>> loadSpeciesIdsWithoutImage(String deckId) async {
    final db = await _db;
    final rows = await db.rawQuery(
      '''
      SELECT m.species_id AS species_id, c.capability AS capability,
             c.state AS state, w.wants_inat_photos AS wants_inat_photos
        FROM $deckMembershipTable m
        LEFT JOIN $capabilityStateTable c ON c.species_id = m.species_id
        LEFT JOIN $speciesWorkTable w ON w.species_id = m.species_id
       WHERE m.deck_id = ?
      ''',
      [deckId],
    );

    final statesBySpecies = <String, Map<String, String>>{};
    final wantsInatPhotosBySpecies = <String, bool>{};
    for (final row in rows) {
      final speciesId = row['species_id'] as String;
      final capability = row['capability'] as String?;
      final state = row['state'] as String?;
      final states = statesBySpecies.putIfAbsent(speciesId, () => {});
      if (capability != null && state != null) {
        states[capability] = state;
      }
      wantsInatPhotosBySpecies[speciesId] =
          (row['wants_inat_photos'] as int? ?? 0) == 1;
    }

    final withoutImage = <String>{};
    for (final entry in statesBySpecies.entries) {
      final baseState = entry.value['base'];
      final primaryState = entry.value['inatPrimary'];
      final wantsInatPhotos = wantsInatPhotosBySpecies[entry.key] ?? false;
      // Same "no inatPrimary row without consent" allowance as
      // loadDeckProjection — a species without iNat-photo consent never gets
      // an inatPrimary row, so its image stage is complete (nothing left to
      // try) the moment `base` is terminal, not just once inatPrimary is too.
      final imageComplete =
          _capabilityStateTerminal.contains(baseState) &&
          (baseState == 'done' ||
              _capabilityStateTerminal.contains(primaryState) ||
              !wantsInatPhotos);
      final hasImage = baseState == 'done' || primaryState == 'done';
      if (imageComplete && !hasImage) {
        withoutImage.add(entry.key);
      }
    }
    return withoutImage;
  }

  /// Species names submitted for [deckId] that were never resolved to a real
  /// species — neither found in the reference DB up front, nor resolvable
  /// via iNaturalist after exhausting the retry budget
  /// ([recordUnresolvedNameAttemptFailure]'s `permanentFailure`).
  Future<List<String>> loadPermanentlyUnresolvedNames(String deckId) async {
    final db = await _db;
    final rows = await db.query(
      unresolvedNamesTable,
      columns: const ['name'],
      where: 'deck_id = ? AND state = ?',
      whereArgs: [deckId, 'permanentFailure'],
      orderBy: 'name ASC',
    );
    return rows.map((row) => row['name'] as String).toList(growable: false);
  }

  static String _capabilityName(EnrichmentStage stage) =>
      stage == EnrichmentStage.names ? 'speciesCommonNames' : stage.name;

  static INatWorkItemKind _workItemKindForCapabilityName(String capability) {
    switch (capability) {
      case 'inatPrimary':
        return INatWorkItemKind.inatPrimary;
      case 'speciesCommonNames':
        return INatWorkItemKind.speciesCommonNames;
      case 'inatBackfill':
        return INatWorkItemKind.inatBackfill;
      default:
        throw ArgumentError('Unknown iNat queue capability: $capability');
    }
  }
}
