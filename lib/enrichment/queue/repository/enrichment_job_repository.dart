import 'dart:convert';

import 'package:discere/enrichment/queue/model/enrichment_job.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:sqflite/sqflite.dart';

/// Persists the deck-cover job — the only job the enrichment queue runs.
/// Species and taxonomy enrichment is tracked in `EnrichmentWorkRepository`'s
/// queue tables instead, driven by `BaseWorker`/`INatWorker`.
///
/// One row per deck in `enrichment_jobs`, carrying both the job's lifecycle
/// (`status`, lease, retry bookkeeping) and how far the cover fetch itself
/// has got (`cover_state`). The two are not redundant: `status` says who is
/// working on the deck and whether it may be claimed, `cover_state` says
/// whether the image is still owed.
class EnrichmentJobRepository {
  static final _log = Logger.forType(EnrichmentJobRepository);
  static const jobsTable = 'enrichment_jobs';

  /// A job in one of these can never be claimed again — the deck is done
  /// with, one way or another.
  static const _terminalStatuses = [
    EnrichmentJobStatus.cancelled,
    EnrichmentJobStatus.completed,
    EnrichmentJobStatus.failedPermanent,
  ];

  final Database? _injectedDb;

  const EnrichmentJobRepository([this._injectedDb]);

  Future<Database> get _db async => _injectedDb ?? DatabaseHelper.userDb;

  Future<void> scheduleDeckJob({
    required String deckId,
    String? coverImageUrl,
  }) async {
    final db = await _db;
    final now = DateTime.now();
    final normalizedCoverUrl = _normalizeNullable(coverImageUrl);
    _log.debug(
      'Schedule cover job deck=$deckId cover=${normalizedCoverUrl != null}',
    );

    await db.transaction((txn) async {
      final existing = await _loadJob(txn, deckId);
      final payload = EnrichmentJobPayload(
        coverImageUrl: normalizedCoverUrl ?? existing?.payload.coverImageUrl,
      );

      // With no cover URL there is nothing to fetch, so the job is born
      // skipped and completed. Left `queued`/`pending` it would never be
      // claimed (claimNextJob only takes a pending cover) and would sit there
      // forever, keeping `coverTerminal` false and the deck out of `done`.
      // `completed_at` stays null: nothing was downloaded, so there is no
      // meaningful completion moment — the deck's session-scoped timestamp
      // (see _resolveLastCompletedAt) covers "when the deck finished".
      final coverSkipped = _normalizeNullable(payload.coverImageUrl) == null;

      await txn.insert(jobsTable, {
        'deck_id': deckId,
        'status': (coverSkipped
                ? EnrichmentJobStatus.completed
                : EnrichmentJobStatus.queued)
            .name,
        'attempted_at': existing?.attemptedAt?.millisecondsSinceEpoch,
        'completed_at': null,
        'cover_state': (coverSkipped
                ? CoverFetchState.skipped
                : CoverFetchState.pending)
            .wireName,
        'payload_json': jsonEncode(payload.toJson()),
        'failure_kind': null,
        'last_error': null,
        'progress_completed': 0,
        'progress_total': 0,
        'retry_count': 0,
        'next_attempt_at': null,
        'lease_owner': null,
        'lease_expires_at': null,
        'updated_at': now.millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  /// Deletes the job row for a deck whose enrichment is being abandoned. The
  /// only caller is deck deletion (`DecksService.onDeckDeleted`), so by the
  /// time this runs the deck itself is already gone — there's no reason to
  /// keep a `cancelled` tombstone. An in-flight write for this deck is safely
  /// discarded elsewhere because it looks the job up by id and finds nothing,
  /// exactly as it would for a soft-cancelled row.
  Future<void> deleteDeckJob(String deckId) async {
    final db = await _db;
    _log.debug('Delete job deck=$deckId');
    await db.delete(jobsTable, where: 'deck_id = ?', whereArgs: [deckId]);
  }

  /// One-time cleanup for job rows left behind by decks deleted before
  /// [deleteDeckJob] replaced the old soft-cancel behavior. [validDeckIds]
  /// empty is treated as "caller doesn't know yet" rather than "there are no
  /// decks" — deleting everything on a transient empty read would be far
  /// worse than occasionally skipping a cleanup pass.
  Future<void> pruneJobsNotIn(Set<String> validDeckIds) async {
    if (validDeckIds.isEmpty) return;
    final db = await _db;
    final placeholders = List.filled(validDeckIds.length, '?').join(',');
    final deletedCount = await db.delete(
      jobsTable,
      where: 'deck_id NOT IN ($placeholders)',
      whereArgs: validDeckIds.toList(growable: false),
    );
    if (deletedCount > 0) {
      _log.debug('Pruned $deletedCount orphaned enrichment job(s)');
    }
  }

  /// Diagnostics escape hatch: cancels every cover job not already terminal,
  /// clearing its lease so it can never be reclaimed and marking its cover
  /// `skipped` so [hasPendingWork] agrees. `EnrichmentJobStatus.cancelled` is
  /// the one status `computeDeckEnrichmentState` treats as `hidden` up front
  /// — deliberately not the same as deleting the row, which instead reads as
  /// trivially "cover-terminal" and would hide an abandoned cover fetch
  /// behind a false `done`. A later [scheduleDeckJob] call (e.g. the Edit-Deck
  /// page's manual "trigger enrichment") always upserts a fresh row
  /// regardless of the previous status, so this doesn't block a real restart.
  /// Returns the number of jobs cancelled.
  Future<int> cancelAllNonTerminalJobs() async {
    final db = await _db;
    final cancelled = await db.update(
      jobsTable,
      {
        'status': EnrichmentJobStatus.cancelled.name,
        'cover_state': CoverFetchState.skipped.wireName,
        'lease_owner': null,
        'lease_expires_at': null,
        'next_attempt_at': null,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'status NOT IN ($_statusPlaceholders)',
      whereArgs: _terminalStatusNames,
    );
    if (cancelled > 0) {
      _log.debug('Cancelled $cancelled non-terminal enrichment job(s)');
    }
    return cancelled;
  }

  Future<bool> isJobActive({required String deckId, String? owner}) async {
    final db = await _db;
    final job = await _loadJob(db, deckId);
    if (job == null || job.status == EnrichmentJobStatus.cancelled) {
      return false;
    }
    if (owner != null && job.leaseOwner != owner) {
      return false;
    }
    return true;
  }

  Future<List<EnrichmentJobRecord>> loadAllJobs() async {
    final db = await _db;
    final rows = await db.query(jobsTable, orderBy: 'updated_at ASC');
    return [for (final row in rows) _buildRecordFromRow(row)];
  }

  /// Loads only jobs whose row changed at or after [since] — every mutation
  /// bumps `updated_at`, so this is a correct "what changed since I last
  /// looked" delta instead of re-reading and re-parsing the full — and, since
  /// nothing ever prunes completed jobs, ever-growing — history on every
  /// poll. Deletions are not visible through this query; callers that delete
  /// a job (see [deleteDeckJob]) must drop it from their own in-memory state
  /// directly.
  ///
  /// Intentionally `>=`, not `>`: `updated_at` has millisecond resolution, so
  /// two jobs updated in the same millisecond are indistinguishable by
  /// timestamp alone. A caller that advances its cursor to the latest
  /// `updated_at` it saw and re-queries with `>` could permanently miss a
  /// sibling row stamped with that same millisecond. `>=` re-fetches
  /// whichever rows share the cursor's exact timestamp on the next call — a
  /// small, bounded overlap — instead of silently dropping updates.
  Future<List<EnrichmentJobRecord>> loadJobsUpdatedSince(DateTime since) async {
    final db = await _db;
    final rows = await db.query(
      jobsTable,
      where: 'updated_at >= ?',
      whereArgs: [since.millisecondsSinceEpoch],
      orderBy: 'updated_at ASC',
    );
    return [for (final row in rows) _buildRecordFromRow(row)];
  }

  Future<EnrichmentJobRecord?> loadJob(String deckId) async {
    final db = await _db;
    return _loadJob(db, deckId);
  }

  Future<bool> hasPendingWork() async {
    final db = await _db;
    final rows = await db.query(
      jobsTable,
      columns: const ['deck_id'],
      where:
          'status NOT IN ($_statusPlaceholders) OR cover_state IN (?, ?)',
      whereArgs: [
        ..._terminalStatusNames,
        CoverFetchState.pending.wireName,
        CoverFetchState.running.wireName,
      ],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Claims the oldest job whose cover is still owed, taking a lease on it.
  ///
  /// Tie-broken by deck id, and `updated_at IS NULL` sorts NULLs last so a row
  /// with no timestamp reads as newest — matching the in-memory record's
  /// `updatedAt ?? now` default.
  Future<EnrichmentJobRecord?> claimNextJob({
    required String owner,
    required Duration leaseDuration,
    required EnrichmentRunnerKind runnerKind,
  }) async {
    final db = await _db;
    return db.transaction((txn) async {
      final now = DateTime.now();
      await _recoverExpiredLeases(txn, now);

      final selectedRows = await txn.query(
        jobsTable,
        columns: const ['deck_id'],
        where:
            'cover_state = ? AND status NOT IN ($_statusPlaceholders) '
            'AND (lease_owner IS NULL OR lease_owner = ?)',
        whereArgs: [
          CoverFetchState.pending.wireName,
          ..._terminalStatusNames,
          owner,
        ],
        orderBy: 'updated_at IS NULL, updated_at ASC, deck_id ASC',
        limit: 1,
      );

      if (selectedRows.isEmpty) {
        _log.debug('No claimable enrichment job for runner=${runnerKind.name}');
        return null;
      }
      final deckId = selectedRows.first['deck_id'] as String;

      await txn.update(
        jobsTable,
        {
          'status': _runningStatusFor(runnerKind).name,
          'next_attempt_at': null,
          'lease_owner': owner,
          'lease_expires_at': now.add(leaseDuration).millisecondsSinceEpoch,
          'updated_at': now.millisecondsSinceEpoch,
        },
        where: 'deck_id = ?',
        whereArgs: [deckId],
      );
      _log.debug(
        'Claim job deck=$deckId runner=${runnerKind.name} owner=$owner',
      );
      return _loadJob(txn, deckId);
    });
  }

  Future<void> markCoverRunning({
    required String deckId,
    required String owner,
    required EnrichmentRunnerKind runnerKind,
  }) async {
    final db = await _db;
    final now = DateTime.now();
    _log.debug(
      'Mark cover running deck=$deckId runner=${runnerKind.name} owner=$owner',
    );
    await db.transaction((txn) async {
      final job = await _loadJob(txn, deckId);
      if (job == null || job.status == EnrichmentJobStatus.cancelled) return;
      await txn.update(
        jobsTable,
        {
          'status': _runningStatusFor(runnerKind).name,
          'cover_state': CoverFetchState.running.wireName,
          'attempted_at': now.millisecondsSinceEpoch,
          'next_attempt_at': null,
          'lease_owner': owner,
          'updated_at': now.millisecondsSinceEpoch,
        },
        where: 'deck_id = ?',
        whereArgs: [deckId],
      );
    });
  }

  /// The cover is the whole job, so succeeding at it completes the job.
  Future<void> markCoverSucceeded({
    required String deckId,
    required String owner,
  }) async {
    final db = await _db;
    await db.transaction((txn) async {
      final now = DateTime.now();
      if (await _loadJobLeasedBy(txn, deckId, owner) == null) return;
      await _updateClaimed(txn, deckId, owner, {
        ..._leaseReleaseFields(now),
        'cover_state': CoverFetchState.succeeded.wireName,
        'status': EnrichmentJobStatus.completed.name,
        'completed_at': now.millisecondsSinceEpoch,
        'failure_kind': null,
        'last_error': null,
        'progress_completed': 0,
        'progress_total': 0,
        'retry_count': 0,
        'next_attempt_at': null,
      });
      _log.debug('Mark cover succeeded deck=$deckId owner=$owner');
    });
  }

  Future<void> markCoverRetryScheduled({
    required String deckId,
    required String owner,
    required String error,
    required String failureKind,
  }) async {
    final db = await _db;
    await db.transaction((txn) async {
      final now = DateTime.now();
      final job = await _loadJobLeasedBy(txn, deckId, owner);
      if (job == null) return;
      final nextRetryCount = job.retryCount + 1;
      final nextAttemptAt = now.add(_retryBackoffFor(nextRetryCount));
      _log.debug(
        'Mark cover retry deck=$deckId owner=$owner kind=$failureKind '
        'error=$error retryCount=$nextRetryCount '
        'nextAttemptAt=$nextAttemptAt',
      );
      await _updateClaimed(txn, deckId, owner, {
        ..._leaseReleaseFields(now),
        'cover_state': CoverFetchState.pending.wireName,
        'status': EnrichmentJobStatus.retryScheduled.name,
        'failure_kind': failureKind,
        'last_error': error,
        'retry_count': nextRetryCount,
        'next_attempt_at': nextAttemptAt.millisecondsSinceEpoch,
      });
    });
  }

  Future<void> markCoverFailedPermanent({
    required String deckId,
    required String owner,
    required String error,
    required String failureKind,
  }) async {
    final db = await _db;
    _log.debug(
      'Mark cover permanent failure deck=$deckId owner=$owner '
      'kind=$failureKind error=$error',
    );
    await db.transaction((txn) async {
      final now = DateTime.now();
      if (await _loadJobLeasedBy(txn, deckId, owner) == null) return;
      await _updateClaimed(txn, deckId, owner, {
        ..._leaseReleaseFields(now),
        'cover_state': CoverFetchState.failed.wireName,
        'status': EnrichmentJobStatus.failedPermanent.name,
        'failure_kind': failureKind,
        'last_error': error,
        'progress_completed': 0,
        'progress_total': 0,
        'retry_count': 0,
        'next_attempt_at': null,
      });
    });
  }

  /// Releases the leases held by [owner] so the jobs can be picked up again,
  /// and rewinds a cover that was mid-flight back to pending.
  Future<void> pauseJobsOwnedBy(String owner) async {
    final db = await _db;
    final now = DateTime.now();
    final paused = await db.update(
      jobsTable,
      {
        'status': EnrichmentJobStatus.pausedBySystem.name,
        'cover_state': CoverFetchState.pending.wireName,
        'lease_owner': null,
        'lease_expires_at': null,
        'updated_at': now.millisecondsSinceEpoch,
      },
      where: 'lease_owner = ?',
      whereArgs: [owner],
    );
    if (paused > 0) {
      _log.debug('Paused $paused job(s) owned by $owner');
    }
  }

  /// Clear the persisted `next_attempt_at` for all jobs currently in
  /// `retryScheduled` status. Called when the host cooldown ends so that
  /// [claimNextJob] picks the jobs up immediately instead of waiting for the
  /// original retry delay (which may be hours away when the actual blocker
  /// has already cleared).
  Future<int> clearRetryAttemptForRetryScheduledJobs() async {
    final db = await _db;
    final count = await db.update(
      jobsTable,
      {'next_attempt_at': null},
      where: 'status = ? AND next_attempt_at IS NOT NULL',
      whereArgs: [EnrichmentJobStatus.retryScheduled.name],
    );
    if (count > 0) {
      _log.debug('Cleared next_attempt_at on $count retryScheduled job(s)');
    }
    return count;
  }

  /// Force-runs the same expired-lease recovery [claimNextJob] already
  /// performs on every claim attempt — exposed for the diagnostics page's
  /// manual "reset stuck jobs" action so a user doesn't have to wait for the
  /// next natural claim cycle. Returns the number of jobs recovered.
  Future<int> recoverExpiredLeases() async {
    final db = await _db;
    return db.transaction((txn) => _recoverExpiredLeases(txn, DateTime.now()));
  }

  Future<int> _recoverExpiredLeases(
    DatabaseExecutor executor,
    DateTime now,
  ) async {
    final recovered = await executor.update(
      jobsTable,
      {
        'status': EnrichmentJobStatus.pausedBySystem.name,
        'cover_state': CoverFetchState.pending.wireName,
        'lease_owner': null,
        'lease_expires_at': null,
        'updated_at': now.millisecondsSinceEpoch,
      },
      where: 'lease_expires_at IS NOT NULL AND lease_expires_at < ?',
      whereArgs: [now.millisecondsSinceEpoch],
    );
    if (recovered > 0) {
      _log.debug('Recovered $recovered expired lease(s)');
    }
    return recovered;
  }

  /// Estimated delay before a `retryScheduled` job should be retried, purely
  /// for the [DeckEnrichmentState.paused] display and its refresh timers (see
  /// `InatEnrichmentQueueService._syncPauseDisplayTimers`). Does not gate
  /// [claimNextJob] — actual request pacing happens in the HTTP layer via
  /// `HostCooldownTracker`. Steps mirror that tracker's default cooldown
  /// progression so the displayed estimate is in the right ballpark.
  static const List<Duration> _retryBackoffSteps = [
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 2),
    Duration(minutes: 4),
  ];

  static Duration _retryBackoffFor(int retryCount) {
    final index = (retryCount - 1).clamp(0, _retryBackoffSteps.length - 1);
    return _retryBackoffSteps[index];
  }

  static EnrichmentJobStatus _runningStatusFor(EnrichmentRunnerKind kind) =>
      kind == EnrichmentRunnerKind.foreground
      ? EnrichmentJobStatus.runningForeground
      : EnrichmentJobStatus.runningBackground;

  static String get _statusPlaceholders =>
      List.filled(_terminalStatuses.length, '?').join(',');

  static List<String> get _terminalStatusNames => [
    for (final status in _terminalStatuses) status.name,
  ];

  /// Loads the job for [deckId] and returns it only if it is still owned by
  /// [owner] and not cancelled — the guard every `markCover*` mutation needs
  /// before touching a job it took a lease on. Null means "nothing to do":
  /// the job was cancelled, deleted, or its lease moved on from under us.
  Future<EnrichmentJobRecord?> _loadJobLeasedBy(
    DatabaseExecutor executor,
    String deckId,
    String owner,
  ) async {
    final job = await _loadJob(executor, deckId);
    if (job == null ||
        job.status == EnrichmentJobStatus.cancelled ||
        job.leaseOwner != owner) {
      return null;
    }
    return job;
  }

  /// The lease is re-checked in the `WHERE` as well as by [_loadJobLeasedBy],
  /// so the write cannot land on a row some other owner claimed in between.
  Future<void> _updateClaimed(
    DatabaseExecutor executor,
    String deckId,
    String owner,
    Map<String, Object?> values,
  ) => executor.update(
    jobsTable,
    values,
    where: 'deck_id = ? AND lease_owner = ?',
    whereArgs: [deckId, owner],
  );

  /// The fields every finished `markCover*` mutation resets identically: the
  /// lease is released and `updated_at` refreshed. Callers spread this and
  /// add whatever else is specific to that outcome.
  Map<String, Object?> _leaseReleaseFields(DateTime now) => {
    'lease_owner': null,
    'lease_expires_at': null,
    'updated_at': now.millisecondsSinceEpoch,
  };

  Future<EnrichmentJobRecord?> _loadJob(
    DatabaseExecutor executor,
    String deckId,
  ) async {
    final rows = await executor.query(
      jobsTable,
      where: 'deck_id = ?',
      whereArgs: [deckId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _buildRecordFromRow(rows.first);
  }

  EnrichmentJobRecord _buildRecordFromRow(Map<String, dynamic> row) {
    final payloadJson = row['payload_json'] as String? ?? '{}';
    return EnrichmentJobRecord(
      deckId: row['deck_id'] as String,
      status: EnrichmentJobStatus.values.byName(row['status'] as String),
      attemptedAt: _millisToDateTime(row['attempted_at'] as int?),
      completedAt: _millisToDateTime(row['completed_at'] as int?),
      payload: EnrichmentJobPayload.fromJson(
        jsonDecode(payloadJson) as Map<String, dynamic>,
      ),
      failureKind: row['failure_kind'] as String?,
      lastError: row['last_error'] as String?,
      progressCompleted: row['progress_completed'] as int? ?? 0,
      progressTotal: row['progress_total'] as int? ?? 0,
      retryCount: row['retry_count'] as int? ?? 0,
      nextAttemptAt: _millisToDateTime(row['next_attempt_at'] as int?),
      leaseOwner: row['lease_owner'] as String?,
      leaseExpiresAt: _millisToDateTime(row['lease_expires_at'] as int?),
      updatedAt: _millisToDateTime(row['updated_at'] as int?) ?? DateTime.now(),
      coverState: CoverFetchState.fromWire(row['cover_state'] as String),
    );
  }

  static DateTime? _millisToDateTime(int? millis) =>
      millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);

  static String? _normalizeNullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
