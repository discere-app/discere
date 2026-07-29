import 'dart:convert';

import 'package:discere/enrichment/model/deck_enrichment_projection.dart';
import 'package:discere/enrichment/model/enrichment_work_plan.dart';
import 'package:discere/enrichment/model/inat_work_item.dart';
import 'package:discere/enrichment/repository/enrichment_job_repository.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:sqflite/sqflite.dart';

/// Terminal-state vocabulary shared by the three new producer-consumer queue
/// tables (`enrichment_species_capability_state`, `enrichment_taxonomy_work`,
/// `enrichment_unresolved_names`) — see GitHub issue #57.
const _capabilityStatePending = 'pending';
const _capabilityStateRetryScheduled = 'retryScheduled';
const _capabilityStateTerminal = {'done', 'noResult', 'permanentFailure'};

class OwnedTaxonomyWorkItem {
  final String workKey;
  final String runtimeEntityKey;
  final String rank;
  final String scientificName;
  final Set<String> speciesIds;

  const OwnedTaxonomyWorkItem({
    required this.workKey,
    required this.runtimeEntityKey,
    required this.rank,
    required this.scientificName,
    required this.speciesIds,
  });
}

class EnrichmentWorkRepository {
  static const speciesWorkTable = 'enrichment_species_work';
  static const taxonomyWorkTable = 'enrichment_taxonomy_work';
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
      final assignments = <String, List<String>>{
        for (final deckId in prioritizedDeckIds) deckId: <String>[],
      };
      final deckPriority = <String, int>{
        for (var index = 0; index < prioritizedDeckIds.length; index++)
          prioritizedDeckIds[index]: index,
      };

      final allSpeciesIds =
          speciesIdsByDeckId.values
              .expand((speciesIds) => speciesIds)
              .toSet()
              .toList(growable: false)
            ..sort((left, right) {
              final leftFrequency = speciesIdsByDeckId.values
                  .where((speciesIds) => speciesIds.contains(left))
                  .length;
              final rightFrequency = speciesIdsByDeckId.values
                  .where((speciesIds) => speciesIds.contains(right))
                  .length;
              final frequencyComparison = rightFrequency.compareTo(
                leftFrequency,
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
          existingRow: existingRow,
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
        final deckIds = _decodeStringList(row['deck_ids_json']);
        final hasTrackedDeck = deckIds.any(deckPriority.containsKey);
        if (!hasTrackedDeck) {
          continue;
        }
        await txn.delete(
          speciesWorkTable,
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
      final deckIds = {
        ..._decodeStringList(existingRow?['deck_ids_json']),
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
        existingRow: existingRow,
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
    required Map<String, Object?>? existingRow,
    required bool wantsInatPhotos,
    required bool wantsCommonNames,
    required int now,
  }) async {
    await txn.insert(speciesWorkTable, {
      'species_id': speciesId,
      'owner_deck_id': ownerDeckId,
      'deck_ids_json': jsonEncode(deckIds),
      'deck_count': deckIds.length,
      'base_state': existingRow?['base_state'] ?? 'pending',
      'inat_primary_state': existingRow?['inat_primary_state'] ?? 'pending',
      'species_common_names_state':
          existingRow?['species_common_names_state'] ?? 'pending',
      'inat_backfill_state': existingRow?['inat_backfill_state'] ?? 'pending',
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
  }

  Future<List<OwnedTaxonomyWorkItem>> assignTaxonomyOwners({
    required String deckId,
    required Iterable<TaxonomyWorkPlanItem> items,
  }) async {
    final db = await _db;
    return db.transaction((txn) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final rows = await txn.query(taxonomyWorkTable);
      final existingByRuntimeEntityKey = {
        for (final row in rows) row['runtime_entity_key'] as String: row,
      };
      final ownedItems = <OwnedTaxonomyWorkItem>[];

      for (final item in items) {
        final existingRow = existingByRuntimeEntityKey[item.runtimeEntityKey];
        final ownerDeckId = existingRow?['owner_deck_id'] as String? ?? deckId;
        final deckIds = {
          ..._decodeStringList(existingRow?['deck_ids_json']),
          deckId,
        }.toList(growable: false)..sort();
        final speciesIds = {
          ..._decodeStringList(existingRow?['species_ids_json']),
          ...item.speciesIds,
        }.toList(growable: false)..sort();
        final workKey = existingRow?['work_key'] as String? ?? item.workKey;
        await txn.insert(taxonomyWorkTable, {
          'work_key': workKey,
          'runtime_entity_key': item.runtimeEntityKey,
          'owner_deck_id': ownerDeckId,
          'deck_ids_json': jsonEncode(deckIds),
          'species_ids_json': jsonEncode(speciesIds),
          'rank': item.rank,
          'scientific_name': item.scientificName,
          'common_names_state': existingRow?['common_names_state'] ?? 'pending',
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        if (ownerDeckId == deckId) {
          ownedItems.add(
            OwnedTaxonomyWorkItem(
              workKey: workKey,
              runtimeEntityKey: item.runtimeEntityKey,
              rank: item.rank,
              scientificName: item.scientificName,
              speciesIds: item.speciesIds,
            ),
          );
        }
      }

      return List<OwnedTaxonomyWorkItem>.unmodifiable(ownedItems);
    });
  }

  /// Returns any deck currently referencing [speciesId], or `null` if none do
  /// (e.g. the species was already fully released). Used when a worker needs
  /// *some* deck to attribute new taxonomy-work ownership to — any deck
  /// sharing the species does equally well, since `assignTaxonomyOwners`'
  /// dedup contract only cares that a real owner exists.
  Future<String?> loadAnyDeckIdForSpecies(String speciesId) async {
    final db = await _db;
    final membershipRows = await db.query(
      deckMembershipTable,
      columns: const ['deck_id'],
      where: 'species_id = ?',
      whereArgs: [speciesId],
      limit: 1,
    );
    if (membershipRows.isNotEmpty) {
      return membershipRows.single['deck_id'] as String;
    }
    final speciesRows = await db.query(
      speciesWorkTable,
      columns: const ['owner_deck_id'],
      where: 'species_id = ?',
      whereArgs: [speciesId],
      limit: 1,
    );
    return speciesRows.isEmpty
        ? null
        : speciesRows.single['owner_deck_id'] as String?;
  }

  /// Species that already reached `succeeded` for [stage], regardless of which
  /// deck owns them. Used by the executor to skip work that another deck has
  /// already completed for overlapping species.
  Future<Set<String>> loadSucceededSpeciesIdsForStage(
    EnrichmentStage stage,
  ) async {
    final column = _speciesStateColumnForStage(stage);
    if (column == null) return const <String>{};
    final db = await _db;
    final rows = await db.query(
      speciesWorkTable,
      columns: const ['species_id'],
      where: '$column = ?',
      whereArgs: const ['succeeded'],
    );
    return {for (final row in rows) row['species_id'] as String};
  }

  Future<void> markSpeciesStageCompleted({
    required EnrichmentStage stage,
    required Iterable<String> speciesIds,
  }) async {
    final normalizedSpeciesIds = _normalizedValues(speciesIds);
    if (normalizedSpeciesIds.isEmpty) return;
    final db = await _db;
    final columnName = _speciesStateColumnForStage(stage);
    if (columnName == null) {
      return;
    }
    await db.update(
      speciesWorkTable,
      {
        columnName: 'succeeded',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where:
          'species_id IN (${List.filled(normalizedSpeciesIds.length, '?').join(', ')})',
      whereArgs: normalizedSpeciesIds,
    );
  }

  Future<void> markTaxonomyCommonNamesCompleted(
    Iterable<String> workKeys,
  ) async {
    final normalizedWorkKeys = _normalizedValues(workKeys);
    if (normalizedWorkKeys.isEmpty) return;
    final db = await _db;
    await db.update(
      taxonomyWorkTable,
      {
        'common_names_state': 'succeeded',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where:
          'work_key IN (${List.filled(normalizedWorkKeys.length, '?').join(', ')})',
      whereArgs: normalizedWorkKeys,
    );
  }

  Future<void> releaseDeck(String deckId) async {
    final normalizedDeckId = deckId.trim();
    if (normalizedDeckId.isEmpty) return;
    final db = await _db;
    await db.transaction((txn) async {
      final speciesRows = await txn.query(speciesWorkTable);
      for (final row in speciesRows) {
        final deckIds = _decodeStringList(row['deck_ids_json'])
          ..removeWhere((value) => value == normalizedDeckId);
        final ownerDeckId = row['owner_deck_id'] as String?;
        if (deckIds.isEmpty || ownerDeckId == normalizedDeckId) {
          await txn.delete(
            speciesWorkTable,
            where: 'species_id = ?',
            whereArgs: [row['species_id']],
          );
          continue;
        }
        await txn.update(
          speciesWorkTable,
          {
            'deck_ids_json': jsonEncode(deckIds),
            'deck_count': deckIds.length,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'species_id = ?',
          whereArgs: [row['species_id']],
        );
      }

      final taxonomyRows = await txn.query(taxonomyWorkTable);
      for (final row in taxonomyRows) {
        final deckIds = _decodeStringList(row['deck_ids_json'])
          ..removeWhere((value) => value == normalizedDeckId);
        final ownerDeckId = row['owner_deck_id'] as String?;
        if (deckIds.isEmpty || ownerDeckId == normalizedDeckId) {
          await txn.delete(
            taxonomyWorkTable,
            where: 'work_key = ?',
            whereArgs: [row['work_key']],
          );
          continue;
        }
        await txn.update(
          taxonomyWorkTable,
          {
            'deck_ids_json': jsonEncode(deckIds),
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'work_key = ?',
          whereArgs: [row['work_key']],
        );
      }

      await txn.delete(
        deckMembershipTable,
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
  Future<void> seedCapability(
    String speciesId,
    EnrichmentStage capability, {
    required int priorityTier,
  }) async {
    final db = await _db;
    await db.insert(capabilityStateTable, {
      'species_id': speciesId,
      'capability': _capabilityName(capability),
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
  /// must be `'done'` or `'noResult'`.
  ///
  /// Distinct from [markTaxonomyCommonNamesCompleted] (which writes
  /// `'succeeded'` and stays in use by the still-running
  /// `EnrichmentJobExecutor` during the dark rollout) so the old and new
  /// worker models never write conflicting vocabularies onto the same
  /// column.
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
  Future<List<String>> claimBaseWorkBatch({required int limit}) async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.transaction((txn) async {
      final rows = await txn.query(
        capabilityStateTable,
        columns: const ['species_id'],
        where:
            "capability = 'base' AND state IN (?, ?) "
            'AND (next_attempt_at IS NULL OR next_attempt_at <= ?)',
        whereArgs: [
          _capabilityStatePending,
          _capabilityStateRetryScheduled,
          now,
        ],
        orderBy: 'updated_at ASC',
        limit: limit,
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
  Future<INatWorkItem?> claimNextINatWorkItem() async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.transaction((txn) async {
      final speciesRows = await txn.query(
        capabilityStateTable,
        where:
            "capability IN ('inatPrimary', 'speciesCommonNames', 'inatBackfill') "
            'AND state IN (?, ?) '
            'AND (next_attempt_at IS NULL OR next_attempt_at <= ?)',
        whereArgs: [
          _capabilityStatePending,
          _capabilityStateRetryScheduled,
          now,
        ],
        orderBy: 'priority_tier ASC, updated_at ASC',
        limit: 1,
      );
      final taxonomyRows = await txn.query(
        taxonomyWorkTable,
        where:
            'common_names_state IN (?, ?) '
            'AND (next_attempt_at IS NULL OR next_attempt_at <= ?)',
        whereArgs: [
          _capabilityStatePending,
          _capabilityStateRetryScheduled,
          now,
        ],
        orderBy: 'updated_at ASC',
        limit: 1,
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
          return INatWorkItem.taxonomy(
            workKey,
            row['runtime_entity_key'] as String,
            _decodeStringList(row['species_ids_json']).toSet(),
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

  /// Deletes [speciesId]'s deck-membership rows once every capability queue
  /// row that exists for it has reached a terminal state. Safe/idempotent
  /// (no-op if nothing is tracked, or if anything is still in flight).
  ///
  /// Correct across all decks referencing the species at once: consent
  /// (`wants_inat_photos`/`wants_common_names`) is OR'd per-species, not
  /// per-deck, so "terminal for every capability this species wants" is the
  /// same fact for every deck that references it — there's no per-deck
  /// variation to account for. `enrichment_species_capability_state` itself
  /// is intentionally left alone (it's the permanent cross-deck dedup cache;
  /// only the membership/progress-tracking rows are pruned).
  Future<void> pruneSpeciesMembershipIfFullyTerminal(String speciesId) async {
    final db = await _db;
    final rows = await db.query(
      capabilityStateTable,
      columns: const ['state'],
      where: 'species_id = ?',
      whereArgs: [speciesId],
    );
    if (rows.isEmpty) return;
    final allTerminal = rows.every(
      (row) => _capabilityStateTerminal.contains(row['state']),
    );
    if (!allTerminal) return;
    await db.delete(
      deckMembershipTable,
      where: 'species_id = ?',
      whereArgs: [speciesId],
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
             c.state AS state
        FROM $deckMembershipTable m
        LEFT JOIN $capabilityStateTable c ON c.species_id = m.species_id
       WHERE m.deck_id = ?
      ''',
      [deckId],
    );

    final statesBySpecies = <String, Map<String, String>>{};
    for (final row in rows) {
      final speciesId = row['species_id'] as String;
      final capability = row['capability'] as String?;
      final state = row['state'] as String?;
      final states = statesBySpecies.putIfAbsent(speciesId, () => {});
      if (capability != null && state != null) {
        states[capability] = state;
      }
    }

    var imageCompleteCount = 0;
    var imageDoneCount = 0;
    var commonNamesWanted = 0;
    var commonNamesTerminal = 0;
    var backfillWanted = 0;
    var backfillTerminal = 0;
    var anyPermanentFailure = false;

    for (final states in statesBySpecies.values) {
      final baseState = states['base'];
      final primaryState = states['inatPrimary'];

      // A species is image-complete once `base` is terminal AND — only if
      // base didn't itself succeed — `inatPrimary` (seeded reactively by
      // BaseWorker exactly when base doesn't succeed) is also terminal. A
      // species whose base succeeded never gets an inatPrimary row at all,
      // so "no row" must count as complete, not incomplete, in that case.
      if (_capabilityStateTerminal.contains(baseState)) {
        if (baseState == 'done') {
          imageCompleteCount++;
        } else if (_capabilityStateTerminal.contains(primaryState)) {
          imageCompleteCount++;
        }
      }
      if (baseState == 'done' || primaryState == 'done') {
        imageDoneCount++;
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
    }

    final taxonomyRows = await db.query(taxonomyWorkTable);
    var taxonomyTotal = 0;
    var taxonomyTerminal = 0;
    for (final row in taxonomyRows) {
      if (!_decodeStringList(row['deck_ids_json']).contains(deckId)) continue;
      taxonomyTotal++;
      final state = row['common_names_state'] as String?;
      if (_capabilityStateTerminal.contains(state)) {
        taxonomyTerminal++;
      }
      if (state == 'permanentFailure') {
        anyPermanentFailure = true;
      }
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
      anyPermanentFailure: anyPermanentFailure,
    );
  }

  /// Returns every deck id whose enrichment state changed after
  /// [sinceMillis] (epoch milliseconds), across all three queue tables —
  /// the cheap "what changed" query a poller uses to only recompute
  /// [loadDeckProjection] for decks that actually moved, the same way
  /// `EnrichmentJobRepository.loadJobsUpdatedSince`'s delta-loading avoids
  /// reprocessing decks that haven't changed.
  Future<Set<String>> loadDeckIdsUpdatedSince(int sinceMillis) async {
    final db = await _db;
    final deckIds = <String>{};

    final capabilityRows = await db.rawQuery(
      '''
      SELECT DISTINCT m.deck_id AS deck_id
        FROM $capabilityStateTable c
        JOIN $deckMembershipTable m ON m.species_id = c.species_id
       WHERE c.updated_at > ?
      ''',
      [sinceMillis],
    );
    for (final row in capabilityRows) {
      deckIds.add(row['deck_id'] as String);
    }

    final taxonomyRows = await db.query(
      taxonomyWorkTable,
      columns: const ['deck_ids_json'],
      where: 'updated_at > ?',
      whereArgs: [sinceMillis],
    );
    for (final row in taxonomyRows) {
      deckIds.addAll(_decodeStringList(row['deck_ids_json']));
    }

    final unresolvedRows = await db.query(
      unresolvedNamesTable,
      columns: const ['deck_id'],
      where: 'updated_at > ?',
      whereArgs: [sinceMillis],
    );
    for (final row in unresolvedRows) {
      deckIds.add(row['deck_id'] as String);
    }

    return deckIds;
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

  static String? _speciesStateColumnForStage(EnrichmentStage stage) {
    switch (stage) {
      case EnrichmentStage.base:
        return 'base_state';
      case EnrichmentStage.inatPrimary:
        return 'inat_primary_state';
      case EnrichmentStage.names:
        return 'species_common_names_state';
      case EnrichmentStage.inatBackfill:
        return 'inat_backfill_state';
      case EnrichmentStage.nameResolution:
      case EnrichmentStage.cover:
        return null;
    }
  }

  static List<String> _normalizedValues(Iterable<String> values) {
    final normalized = <String>[];
    final seen = <String>{};
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) {
        continue;
      }
      normalized.add(trimmed);
    }
    return normalized;
  }

  static List<String> _decodeStringList(Object? rawValue) {
    if (rawValue is! String || rawValue.isEmpty) {
      return <String>[];
    }
    final decoded = jsonDecode(rawValue);
    if (decoded is! List) {
      return <String>[];
    }
    return decoded
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
  }
}
