import 'package:discere/enrichment/model/enrichment_capability.dart';
import 'package:discere/enrichment/model/enrichment_work_state.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_tables.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:sqflite/sqflite.dart';

/// Operational resets over the queue, none of them part of a worker's loop.
///
/// Their callers are the queue service (refreshing stale reference images,
/// re-triggering a deck) and the diagnostics page (recovering after a crash,
/// abandoning everything outstanding) — which is why they sit apart from
/// claiming and outcome reporting rather than beside them.
class EnrichmentWorkMaintenanceRepository {
  final Database? _injectedDb;

  const EnrichmentWorkMaintenanceRepository([this._injectedDb]);

  Future<Database> get _db async => _injectedDb ?? DatabaseHelper.userDb;

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
}
