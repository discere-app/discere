import 'package:discere/enrichment/model/enrichment_capability.dart';
import 'package:discere/enrichment/model/enrichment_work_state.dart';
import 'package:discere/enrichment/pipeline/model/enrichment_work_plan.dart';
import 'package:discere/enrichment/pipeline/model/inat_work_item.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_tables.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:sqflite/sqflite.dart';

class EnrichmentWorkRepository {

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
      final existingRows = await txn.query(EnrichmentWorkTables.speciesWork);
      final existingBySpeciesId = {
        for (final row in existingRows) row['species_id'] as String: row,
      };
      final existingMembershipRows = await txn.query(EnrichmentWorkTables.deckMembership);
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
    EnrichmentCapability capability, {
    required int priorityTier,
  }) async {
    final capabilityName = capability.wireName;
    final db = await _db;
    if (capabilityName == 'inatPrimary' || capabilityName == 'inatBackfill') {
      final speciesRows = await db.query(
        EnrichmentWorkTables.speciesWork,
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
    await db.insert(EnrichmentWorkTables.capabilityState, {
      'species_id': speciesId,
      'capability': capabilityName,
      'state': pendingState,
      'priority_tier': priorityTier,
      'attempt_count': 0,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// Marks [speciesId]/[capability] terminal with a non-failure outcome:
  /// [EnrichmentWorkState.done] or [EnrichmentWorkState.noResult].
  /// Permanent failure goes through
  /// [recordCapabilityAttemptFailure] instead, since that path needs the
  /// attempt-count bookkeeping).
  ///
  /// [referenceDbVersion], when given, stamps the reference-DB version that
  /// was installed at completion time — only meaningful for the `base`
  /// capability (see `BaseWorker`), which is the only caller that passes it.
  Future<void> markCapabilityTerminal(
    String speciesId,
    EnrichmentCapability capability,
    EnrichmentWorkState state, {
    int? referenceDbVersion,
  }) {
    return _markTerminal(
      table: EnrichmentWorkTables.capabilityState,
      stateColumn: 'state',
      whereClause: 'species_id = ? AND capability = ?',
      whereArgs: [speciesId, capability.wireName],
      state: state,
      referenceDbVersion: referenceDbVersion,
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
    EnrichmentCapability capability, {
    required int maxAttempts,
    required List<Duration> backoffSteps,
    String? error,
    String? failureKind,
  }) {
    return _recordAttemptFailure(
      table: EnrichmentWorkTables.capabilityState,
      stateColumn: 'state',
      whereClause: 'species_id = ? AND capability = ?',
      whereArgs: [speciesId, capability.wireName],
      maxAttempts: maxAttempts,
      backoffSteps: backoffSteps,
      error: error,
      failureKind: failureKind,
    );
  }

  /// Marks [workKey]'s taxonomy common-names capability terminal with a
  /// non-failure outcome: [EnrichmentWorkState.done] or
  /// [EnrichmentWorkState.noResult]. Permanent failure goes through
  /// [recordTaxonomyCapabilityAttemptFailure] instead, since that path needs
  /// the attempt-count bookkeeping.
  Future<void> markTaxonomyCapabilityTerminal(
    String workKey,
    EnrichmentWorkState state,
  ) {
    return _markTerminal(
      table: EnrichmentWorkTables.taxonomyWork,
      stateColumn: 'common_names_state',
      whereClause: 'work_key = ?',
      whereArgs: [workKey],
      state: state,
    );
  }

  /// Same retry/give-up bookkeeping as [recordCapabilityAttemptFailure], but
  /// for a taxonomy work item (keyed by `work_key` on [EnrichmentWorkTables.taxonomyWork]
  /// instead of `(species_id, capability)` on [EnrichmentWorkTables.capabilityState]).
  Future<bool> recordTaxonomyCapabilityAttemptFailure(
    String workKey, {
    required int maxAttempts,
    required List<Duration> backoffSteps,
    String? error,
    String? failureKind,
  }) {
    return _recordAttemptFailure(
      table: EnrichmentWorkTables.taxonomyWork,
      stateColumn: 'common_names_state',
      whereClause: 'work_key = ?',
      whereArgs: [workKey],
      maxAttempts: maxAttempts,
      backoffSteps: backoffSteps,
      error: error,
      failureKind: failureKind,
    );
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

  /// Removes a successfully-resolved (or permanently abandoned) unresolved
  /// name — there's nothing left to track once either happens.
  Future<void> deleteUnresolvedName(String deckId, String name) async {
    final db = await _db;
    await db.delete(
      EnrichmentWorkTables.unresolvedNames,
      where: 'deck_id = ? AND name = ?',
      whereArgs: [deckId, name],
    );
  }

  /// Same retry/give-up bookkeeping as [recordCapabilityAttemptFailure], but
  /// for an unresolved-name item (keyed by `(deck_id, name)` on
  /// [EnrichmentWorkTables.unresolvedNames]). Unlike the other queue tables, giving up here
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
      table: EnrichmentWorkTables.unresolvedNames,
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
    required EnrichmentWorkState state,
    int? referenceDbVersion,
  }) async {
    final db = await _db;
    final values = <String, Object?>{
      stateColumn: state.wireName,
      'attempt_count': 0,
      'next_attempt_at': null,
      'last_error': null,
      'last_failure_kind': null,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    };
    if (referenceDbVersion != null) {
      values['reference_db_version'] = referenceDbVersion;
    }
    await db.update(table, values, where: whereClause, whereArgs: whereArgs);
  }

  /// Shared implementation behind [recordCapabilityAttemptFailure],
  /// [recordTaxonomyCapabilityAttemptFailure], and
  /// [recordUnresolvedNameAttemptFailure] — same escalating-backoff/give-up
  /// policy, different table/state-column/key shape. [hasFailureKindColumn]
  /// is false for [EnrichmentWorkTables.unresolvedNames], which has no `last_failure_kind`
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
      stateColumn: gaveUp ? EnrichmentWorkState.permanentFailure.wireName : retryScheduledState,
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
  /// Requires an existing [EnrichmentWorkTables.deckMembership] row — a species can be
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
          FROM ${EnrichmentWorkTables.capabilityState} c
         WHERE c.capability = 'base'
           AND c.state IN (?, ?)
           AND (c.next_attempt_at IS NULL OR c.next_attempt_at <= ?)
           AND EXISTS (
             SELECT 1 FROM ${EnrichmentWorkTables.deckMembership} m
              WHERE m.species_id = c.species_id
           )
         ORDER BY c.updated_at ASC
         LIMIT ?
        ''',
        [pendingState, retryScheduledState, now, limit],
      );
      final speciesIds = rows
          .map((row) => row['species_id'] as String)
          .toList(growable: false);
      if (speciesIds.isEmpty) return const <String>[];
      await txn.update(
        EnrichmentWorkTables.capabilityState,
        {'state': runningState, 'updated_at': now},
        where:
            "capability = 'base' AND species_id IN "
            '(${List.filled(speciesIds.length, '?').join(', ')})',
        whereArgs: speciesIds,
      );
      return speciesIds;
    });
  }

  /// Resets stale `base` capability rows back to `pending` — terminal
  /// (`done` or `noResult`) and stamped with a `reference_db_version` older
  /// than [currentReferenceDbVersion], or never stamped at all (`NULL`, a row
  /// that completed before that column existed) — so [claimBaseWorkBatch]
  /// reclaims them and `BaseWorker` re-checks the species against the
  /// now-installed reference DB.
  ///
  /// When [deckId] is given, scoped to that deck's member species (like
  /// [loadDeckProjection]) — used by the Edit Deck manual refresh. When
  /// omitted, scoped to every species with at least one deck membership
  /// (mirrors [claimBaseWorkBatch]'s "skip orphaned species" guard) — used by
  /// the global post-reference-DB-update prompt. Manual, user-triggered only
  /// — never run automatically. Returns the number of rows reset.
  ///
  /// This does not itself cause a real re-download for most reprocessed
  /// species: `BaseImageEnrichmentService` delegates to `ImageService`,
  /// which derives the local file path purely from `md5(pictureUrl)` and
  /// skips the HTTP request whenever that path already exists on disk (see
  /// `ImageService._resolveExistingImagePath`). So resetting a species back
  /// to `pending` only triggers actual network traffic when its reference
  /// picture URL genuinely changed since the last successful download — the
  /// common case (URL unchanged) is a cheap disk-existence check.
  Future<int> resetStaleBaseCapability({
    String? deckId,
    required int currentReferenceDbVersion,
  }) async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final membershipClause = deckId != null
        ? 'AND species_id IN (SELECT species_id FROM ${EnrichmentWorkTables.deckMembership} WHERE deck_id = ?)'
        : 'AND species_id IN (SELECT species_id FROM ${EnrichmentWorkTables.deckMembership})';
    return db.update(
      EnrichmentWorkTables.capabilityState,
      {
        'state': pendingState,
        'attempt_count': 0,
        'next_attempt_at': null,
        'last_error': null,
        'last_failure_kind': null,
        'updated_at': now,
      },
      where:
          "capability = '${EnrichmentCapability.base.wireName}' "
          'AND state IN (${sqlList(resolvedStates)}) '
          'AND (reference_db_version IS NULL OR reference_db_version < ?) '
          '$membershipClause',
      whereArgs: [currentReferenceDbVersion, ?deckId],
    );
  }

  /// Count of species (distinct) with a stale `base` capability, per the same
  /// staleness rule as [resetStaleBaseCapability] — used to decide whether
  /// the global post-reference-DB-update prompt should appear at all, and to
  /// render the count in its copy. See [resetStaleBaseCapability] for the
  /// [deckId] scoping contract.
  Future<int> countStaleBaseSpecies({
    String? deckId,
    required int currentReferenceDbVersion,
  }) async {
    final db = await _db;
    final membershipClause = deckId != null
        ? 'AND m.deck_id = ?'
        : '';
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(DISTINCT c.species_id) AS count
        FROM ${EnrichmentWorkTables.capabilityState} c
        JOIN ${EnrichmentWorkTables.deckMembership} m ON m.species_id = c.species_id
       WHERE c.capability = '${EnrichmentCapability.base.wireName}'
         AND c.state IN (${sqlList(resolvedStates)})
         AND (c.reference_db_version IS NULL OR c.reference_db_version < ?)
         $membershipClause
      ''',
      [currentReferenceDbVersion, ?deckId],
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  /// Resets *every* terminal `base` capability row for [deckId]'s member
  /// species back to `pending` — regardless of `reference_db_version` —
  /// so [claimBaseWorkBatch] reclaims them and `BaseWorker` genuinely
  /// re-verifies each species against the local image cache (see
  /// [resetStaleBaseCapability]'s doc comment for why that's normally cheap:
  /// a species whose reference-picture URL — and cached file — are still
  /// valid resolves instantly with no network call).
  ///
  /// Unlike [resetStaleBaseCapability] (which only targets rows genuinely
  /// stamped with an older reference-DB version, and deliberately skips
  /// `permanentFailure`), this also resets `permanentFailure` rows — a
  /// manual "try again" should retry those too — and is not staleness-gated
  /// at all, since the point is an explicit, user-requested full
  /// re-verification (Edit Deck's "Erneut anreichern"/"Jetzt anreichern"),
  /// not an automatic/opportunistic refresh. A deck whose species have no
  /// `base` row yet (never enriched at all) is unaffected — nothing to
  /// reset, `assignSpeciesOwners` seeds it fresh as usual. Returns the
  /// number of rows reset.
  Future<int> resetBaseCapabilityForRetrigger(String deckId) async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.update(
      EnrichmentWorkTables.capabilityState,
      {
        'state': pendingState,
        'attempt_count': 0,
        'next_attempt_at': null,
        'last_error': null,
        'last_failure_kind': null,
        'updated_at': now,
      },
      where:
          "capability = '${EnrichmentCapability.base.wireName}' "
          'AND state IN (${sqlList(terminalStates)}) '
          'AND species_id IN (SELECT species_id FROM ${EnrichmentWorkTables.deckMembership} WHERE deck_id = ?)',
      whereArgs: [deckId],
    );
  }

  /// Claims the single highest-priority pending item across
  /// `inatPrimary`/`speciesCommonNames`/`inatBackfill` (from
  /// [EnrichmentWorkTables.capabilityState]), `taxonomyCommonNames` (from [EnrichmentWorkTables.taxonomyWork])
  /// and `nameResolution` (from [EnrichmentWorkTables.unresolvedNames]) — the shared queue a
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
  /// The species query requires an existing [EnrichmentWorkTables.deckMembership] row for
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
          FROM ${EnrichmentWorkTables.capabilityState} c
         WHERE c.capability IN ('inatPrimary', 'speciesCommonNames', 'inatBackfill')
           AND c.state IN (?, ?)
           AND (c.next_attempt_at IS NULL OR c.next_attempt_at <= ?)
           AND EXISTS (
             SELECT 1 FROM ${EnrichmentWorkTables.deckMembership} m
              WHERE m.species_id = c.species_id
           )
         ORDER BY c.priority_tier ASC, c.updated_at ASC
         LIMIT 1
        ''',
        [pendingState, retryScheduledState, now],
      );
      // Guard like the species claim: only claim a taxonomy row if at least
      // one of its species still has a deck-membership row, so an orphaned
      // taxon (every referencing deck deleted) never burns an iNat request.
      final taxonomyRows = await txn.rawQuery(
        '''
        SELECT t.work_key AS work_key,
               t.runtime_entity_key AS runtime_entity_key
          FROM ${EnrichmentWorkTables.taxonomyWork} t
         WHERE t.common_names_state IN (?, ?)
           AND (t.next_attempt_at IS NULL OR t.next_attempt_at <= ?)
           AND EXISTS (
             SELECT 1 FROM ${EnrichmentWorkTables.taxonomyWorkSpecies} ts
             JOIN ${EnrichmentWorkTables.deckMembership} m ON m.species_id = ts.species_id
              WHERE ts.work_key = t.work_key
           )
         ORDER BY t.updated_at ASC
         LIMIT 1
        ''',
        [pendingState, retryScheduledState, now],
      );
      final unresolvedRows = await txn.query(
        EnrichmentWorkTables.unresolvedNames,
        where:
            'state IN (?, ?) AND (next_attempt_at IS NULL OR next_attempt_at <= ?)',
        whereArgs: [
          pendingState,
          retryScheduledState,
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
            EnrichmentWorkTables.capabilityState,
            {'state': runningState, 'updated_at': now},
            where: 'species_id = ? AND capability = ?',
            whereArgs: [speciesId, capability],
          );
          return INatWorkItem.species(
            _workItemKindFor(EnrichmentCapability.fromWire(capability)),
            speciesId,
            priorityTier: row['priority_tier'] as int,
          );
        case 'taxonomy':
          final row = taxonomyRows.single;
          final workKey = row['work_key'] as String;
          await txn.update(
            EnrichmentWorkTables.taxonomyWork,
            {'common_names_state': runningState, 'updated_at': now},
            where: 'work_key = ?',
            whereArgs: [workKey],
          );
          final taxonomySpeciesRows = await txn.query(
            EnrichmentWorkTables.taxonomyWorkSpecies,
            columns: const ['species_id'],
            where: 'work_key = ?',
            whereArgs: [workKey],
          );
          return INatWorkItem.taxonomy(
            workKey,
            row['runtime_entity_key'] as String,
            {for (final r in taxonomySpeciesRows) r['species_id'] as String},
          );
        case 'unresolvedName':
          final row = unresolvedRows.single;
          final deckId = row['deck_id'] as String;
          final name = row['name'] as String;
          await txn.update(
            EnrichmentWorkTables.unresolvedNames,
            {'state': runningState, 'updated_at': now},
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
      EnrichmentWorkTables.capabilityState,
      {'next_attempt_at': null},
      where: 'state = ? AND next_attempt_at IS NOT NULL',
      whereArgs: [retryScheduledState],
    );
    count += await db.update(
      EnrichmentWorkTables.taxonomyWork,
      {'next_attempt_at': null},
      where: 'common_names_state = ? AND next_attempt_at IS NOT NULL',
      whereArgs: [retryScheduledState],
    );
    count += await db.update(
      EnrichmentWorkTables.unresolvedNames,
      {'next_attempt_at': null},
      where: 'state = ? AND next_attempt_at IS NOT NULL',
      whereArgs: [retryScheduledState],
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
      EnrichmentWorkTables.capabilityState,
      {'state': pendingState},
      where: 'state = ?',
      whereArgs: [runningState],
    );
    await db.update(
      EnrichmentWorkTables.taxonomyWork,
      {'common_names_state': pendingState},
      where: 'common_names_state = ?',
      whereArgs: [runningState],
    );
    await db.update(
      EnrichmentWorkTables.unresolvedNames,
      {'state': pendingState},
      where: 'state = ?',
      whereArgs: [runningState],
    );
  }

  /// Diagnostics escape hatch: deletes every non-terminal row in
  /// [EnrichmentWorkTables.capabilityState]/[EnrichmentWorkTables.taxonomyWork]/[EnrichmentWorkTables.unresolvedNames] —
  /// i.e. abandons all outstanding species/taxonomy/name-resolution work,
  /// app-wide. `enrichment_species_work` (ownership/consent) is left
  /// untouched. Unlike marking these rows terminal, deleting them lets a
  /// later `assignSpeciesOwners`/`seedCapability` call — e.g. from the
  /// Edit-Deck page's manual "trigger enrichment" — actually re-seed a fresh
  /// `pending` row: every seed insert uses `ConflictAlgorithm.ignore`, so it
  /// no-ops as long as *any* row (terminal or not) still exists for that
  /// species/taxon. Returns the number of rows removed.
  Future<int> deleteAllNonTerminalWork() async {
    final db = await _db;
    final terminalPlaceholders = List.filled(
      terminalStates.length,
      '?',
    ).join(',');
    return db.transaction((txn) async {
      final removedCapabilities = await txn.delete(
        EnrichmentWorkTables.capabilityState,
        where: 'state NOT IN ($terminalPlaceholders)',
        whereArgs: terminalStates,
      );

      final staleTaxonomyRows = await txn.query(
        EnrichmentWorkTables.taxonomyWork,
        columns: const ['work_key'],
        where: 'common_names_state NOT IN ($terminalPlaceholders)',
        whereArgs: terminalStates,
      );
      var removedTaxonomy = 0;
      if (staleTaxonomyRows.isNotEmpty) {
        final workKeys = [
          for (final row in staleTaxonomyRows) row['work_key'] as String,
        ];
        final workKeyPlaceholders = List.filled(workKeys.length, '?').join(',');
        await txn.delete(
          EnrichmentWorkTables.taxonomyWorkSpecies,
          where: 'work_key IN ($workKeyPlaceholders)',
          whereArgs: workKeys,
        );
        removedTaxonomy = await txn.delete(
          EnrichmentWorkTables.taxonomyWork,
          where: 'work_key IN ($workKeyPlaceholders)',
          whereArgs: workKeys,
        );
      }

      final removedUnresolvedNames = await txn.delete(
        EnrichmentWorkTables.unresolvedNames,
        where: 'state != ?',
        whereArgs: [EnrichmentWorkState.permanentFailure.wireName],
      );

      return removedCapabilities + removedTaxonomy + removedUnresolvedNames;
    });
  }

  /// The iNaturalist work item a claimed capability row turns into.
  /// [EnrichmentCapability.base] never reaches this path — it is drained by
  /// `BaseWorker` against the bundled catalog, not by the iNat consumer.
  static INatWorkItemKind _workItemKindFor(EnrichmentCapability capability) {
    switch (capability) {
      case EnrichmentCapability.inatPrimary:
        return INatWorkItemKind.inatPrimary;
      case EnrichmentCapability.speciesCommonNames:
        return INatWorkItemKind.speciesCommonNames;
      case EnrichmentCapability.inatBackfill:
        return INatWorkItemKind.inatBackfill;
      case EnrichmentCapability.base:
        throw ArgumentError.value(
          capability,
          'capability',
          'base is drained by BaseWorker, never claimed as an iNat work item',
        );
    }
  }
}
