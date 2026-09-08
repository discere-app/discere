import 'package:discere/enrichment/model/enrichment_capability.dart';
import 'package:discere/enrichment/model/enrichment_work_state.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_tables.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:sqflite/sqflite.dart';

/// How an attempt on a claimed work item ended: done, no result, a
/// scheduled retry, or given up on.
///
/// The three `record*AttemptFailure` methods share [_recordAttemptFailure],
/// which decides between another retry and a permanent failure by comparing
/// the attempt count against the caller's budget — the one rule the three
/// queue tables genuinely have in common, which is why they are one class
/// rather than one per table.
class EnrichmentWorkOutcomeRepository {
  final Database? _injectedDb;

  const EnrichmentWorkOutcomeRepository([this._injectedDb]);

  Future<Database> get _db async => _injectedDb ?? DatabaseHelper.userDb;

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
}
