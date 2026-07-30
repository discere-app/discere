import 'dart:convert';

import 'package:discere/enrichment/queue/model/enrichment_job.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:sqflite/sqflite.dart';

export 'package:discere/enrichment/queue/model/enrichment_job.dart';

/// Persists the deck-cover job — the only job left after the
/// producer-consumer rewrite (see the enrichment-optimization plan / GitHub
/// issues #56, #57). Species/taxonomy enrichment is tracked in
/// `EnrichmentWorkRepository`'s queue tables instead, driven by `BaseWorker`/
/// `INatWorker` rather than a claimed job stage.
///
/// The job model types (status/stage enums, payload, record) live in
/// enrichment/model/enrichment_job.dart and are re-exported here because they
/// are part of this repository's API surface.
class EnrichmentJobRepository {
  static final _log = Logger.forType(EnrichmentJobRepository);
  static const jobsTable = 'enrichment_jobs';
  static const stagesTable = 'enrichment_job_stages';

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

      await txn.insert(jobsTable, {
        'deck_id': deckId,
        'status': EnrichmentJobStatus.queued.name,
        'attempted_at': existing?.attemptedAt?.millisecondsSinceEpoch,
        'completed_at': null,
        'current_stage': null,
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

      await _upsertStage(
        txn,
        deckId,
        EnrichmentStage.cover,
        _normalizeNullable(payload.coverImageUrl) == null
            ? EnrichmentStageState.skipped
            : EnrichmentStageState.pending,
        now,
      );
    });
  }

  /// Deletes the job and its stage rows for a deck whose enrichment is being
  /// abandoned. The only caller is deck deletion (`DecksService.onDeckDeleted`),
  /// so by the time this runs the deck itself is already gone — there's no
  /// reason to keep the row around as a `cancelled` tombstone. An in-flight
  /// stage write for this deck is safely discarded elsewhere because it looks
  /// the job up by id and finds nothing, exactly as it would for a
  /// soft-cancelled row.
  Future<void> deleteDeckJob(String deckId) async {
    final db = await _db;
    _log.debug('Delete job deck=$deckId');
    await db.transaction((txn) async {
      await txn.delete(stagesTable, where: 'deck_id = ?', whereArgs: [deckId]);
      await txn.delete(jobsTable, where: 'deck_id = ?', whereArgs: [deckId]);
    });
  }

  /// One-time cleanup for job/stage rows left behind by decks deleted before
  /// [deleteDeckJob] replaced the old soft-cancel behavior. [validDeckIds]
  /// empty is treated as "caller doesn't know yet" rather than "there are no
  /// decks" — deleting everything on a transient empty read would be far
  /// worse than occasionally skipping a cleanup pass.
  Future<void> pruneJobsNotIn(Set<String> validDeckIds) async {
    if (validDeckIds.isEmpty) return;
    final db = await _db;
    final placeholders = List.filled(validDeckIds.length, '?').join(',');
    final args = validDeckIds.toList(growable: false);
    await db.transaction((txn) async {
      final deletedCount = await txn.delete(
        jobsTable,
        where: 'deck_id NOT IN ($placeholders)',
        whereArgs: args,
      );
      await txn.delete(
        stagesTable,
        where: 'deck_id NOT IN ($placeholders)',
        whereArgs: args,
      );
      if (deletedCount > 0) {
        _log.debug('Pruned $deletedCount orphaned enrichment job(s)');
      }
    });
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
    return _loadAllJobsBatched(db);
  }

  /// Loads only jobs whose row changed at or after [since] — every mutation
  /// on a job (including its stage transitions, which are always written in
  /// the same transaction) bumps `updated_at`, so this is a correct "what
  /// changed since I last looked" delta instead of re-reading and
  /// re-parsing the full — and, since nothing ever prunes completed jobs,
  /// ever-growing — history on every poll. Deletions are not visible
  /// through this query; callers that delete a job (see [deleteDeckJob])
  /// must drop it from their own in-memory state directly.
  ///
  /// Intentionally `>=`, not `>`: `updated_at` has millisecond resolution,
  /// so two jobs updated in the same millisecond are indistinguishable by
  /// timestamp alone. A caller that advances its cursor to the latest
  /// `updated_at` it saw and re-queries with `>` could permanently miss a
  /// sibling row stamped with that same millisecond. `>=` re-fetches
  /// whichever rows share the cursor's exact timestamp on the next call —
  /// a small, bounded overlap — instead of silently dropping updates.
  Future<List<EnrichmentJobRecord>> loadJobsUpdatedSince(DateTime since) async {
    final db = await _db;
    final jobRows = await db.query(
      jobsTable,
      where: 'updated_at >= ?',
      whereArgs: [since.millisecondsSinceEpoch],
      orderBy: 'updated_at ASC',
    );
    if (jobRows.isEmpty) return const [];
    final deckIds = [for (final row in jobRows) row['deck_id'] as String];
    final placeholders = List.filled(deckIds.length, '?').join(',');
    final stageRows = await db.query(
      stagesTable,
      where: 'deck_id IN ($placeholders)',
      whereArgs: deckIds,
    );
    final stagesByDeck = <String, List<Map<String, dynamic>>>{};
    for (final row in stageRows) {
      final deckId = row['deck_id'] as String;
      (stagesByDeck[deckId] ??= []).add(row);
    }
    return [
      for (final row in jobRows)
        _buildRecordFromRow(
          row,
          stagesByDeck[row['deck_id'] as String] ?? const [],
        ),
    ];
  }

  Future<EnrichmentJobRecord?> loadJob(String deckId) async {
    final db = await _db;
    return _loadJob(db, deckId);
  }

  Future<bool> hasPendingWork() async {
    final db = await _db;
    final rows = await db.query(
      jobsTable,
      columns: ['deck_id'],
      where:
          'status NOT IN (?, ?, ?) OR EXISTS (SELECT 1 FROM $stagesTable s WHERE s.deck_id = $jobsTable.deck_id AND s.state IN (?, ?))',
      whereArgs: [
        EnrichmentJobStatus.cancelled.name,
        EnrichmentJobStatus.completed.name,
        EnrichmentJobStatus.failedPermanent.name,
        EnrichmentStageState.pending.name,
        EnrichmentStageState.running.name,
      ],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<EnrichmentJobRecord?> claimNextJob({
    required String owner,
    required Duration leaseDuration,
    required EnrichmentRunnerKind runnerKind,
  }) async {
    final db = await _db;
    return db.transaction((txn) async {
      final now = DateTime.now();
      await _recoverExpiredLeases(txn, now);

      final jobs = await _loadAllJobsBatched(txn);
      EnrichmentJobRecord? selectedJob;
      EnrichmentStage? selectedStage;
      for (final job in jobs) {
        if (!job.hasPendingWork) continue;
        if (job.leaseOwner != null && job.leaseOwner != owner) continue;
        final nextStage = _nextRunnableStage(job);
        if (nextStage == null) continue;
        if (selectedJob == null ||
            job.updatedAt.isBefore(selectedJob.updatedAt) ||
            (job.updatedAt.isAtSameMomentAs(selectedJob.updatedAt) &&
                job.deckId.compareTo(selectedJob.deckId) < 0)) {
          selectedJob = job;
          selectedStage = nextStage;
        }
      }

      if (selectedJob != null && selectedStage != null) {
        final deckId = selectedJob.deckId;

        await txn.update(
          jobsTable,
          {
            'status': runnerKind == EnrichmentRunnerKind.foreground
                ? EnrichmentJobStatus.runningForeground.name
                : EnrichmentJobStatus.runningBackground.name,
            'next_attempt_at': null,
            'lease_owner': owner,
            'lease_expires_at': now.add(leaseDuration).millisecondsSinceEpoch,
            'updated_at': now.millisecondsSinceEpoch,
          },
          where: 'deck_id = ?',
          whereArgs: [deckId],
        );
        _log.debug(
          'Claim job deck=$deckId runner=${runnerKind.name} owner=$owner '
          'stage=${selectedStage.name}',
        );
        return _loadJob(txn, deckId);
      }
      _log.debug('No claimable enrichment job for runner=${runnerKind.name}');
      return null;
    });
  }

  Future<void> markStageRunning({
    required String deckId,
    required EnrichmentStage stage,
    required String owner,
    required EnrichmentRunnerKind runnerKind,
  }) async {
    final db = await _db;
    final now = DateTime.now();
    _log.debug(
      'Mark stage running deck=$deckId stage=${stage.name} '
      'runner=${runnerKind.name} owner=$owner',
    );
    await db.transaction((txn) async {
      final job = await _loadJob(txn, deckId);
      if (job == null || job.status == EnrichmentJobStatus.cancelled) return;
      await _upsertStage(txn, deckId, stage, EnrichmentStageState.running, now);
      await txn.update(
        jobsTable,
        {
          'status': runnerKind == EnrichmentRunnerKind.foreground
              ? EnrichmentJobStatus.runningForeground.name
              : EnrichmentJobStatus.runningBackground.name,
          'attempted_at': now.millisecondsSinceEpoch,
          'current_stage': stage.name,
          'next_attempt_at': null,
          'lease_owner': owner,
          'updated_at': now.millisecondsSinceEpoch,
        },
        where: 'deck_id = ?',
        whereArgs: [deckId],
      );
    });
  }

  /// Marks [stage] succeeded. Since `cover` is the only stage a job can ever
  /// run, this always completes the whole job — there's no next stage to
  /// hand off to.
  Future<void> markStageSucceeded({
    required String deckId,
    required EnrichmentStage stage,
    required String owner,
  }) async {
    final db = await _db;
    await db.transaction((txn) async {
      final now = DateTime.now();
      final job = await _loadJobLeasedBy(txn, deckId, owner);
      if (job == null) return;
      await _upsertStage(
        txn,
        deckId,
        stage,
        EnrichmentStageState.succeeded,
        now,
      );
      await txn.update(
        jobsTable,
        {
          ..._leaseReleaseFields(now),
          'status': EnrichmentJobStatus.completed.name,
          'completed_at': now.millisecondsSinceEpoch,
          'failure_kind': null,
          'last_error': null,
          'progress_completed': 0,
          'progress_total': 0,
          'retry_count': 0,
          'next_attempt_at': null,
        },
        where: 'deck_id = ? AND lease_owner = ?',
        whereArgs: [deckId, owner],
      );
      _log.debug(
        'Mark stage succeeded deck=$deckId stage=${stage.name} owner=$owner',
      );
    });
  }

  Future<void> markStageRetryScheduled({
    required String deckId,
    required EnrichmentStage stage,
    required String owner,
    required String error,
    required String failureKind,
  }) async {
    final db = await _db;
    final now = DateTime.now();
    await db.transaction((txn) async {
      final job = await _loadJobLeasedBy(txn, deckId, owner);
      if (job == null) return;
      final nextRetryCount = job.retryCount + 1;
      final nextAttemptAt = now.add(_retryBackoffFor(nextRetryCount));
      _log.debug(
        'Mark stage retry deck=$deckId stage=${stage.name} owner=$owner '
        'kind=$failureKind error=$error retryCount=$nextRetryCount '
        'nextAttemptAt=$nextAttemptAt',
      );
      await _upsertStage(txn, deckId, stage, EnrichmentStageState.pending, now);
      await txn.update(
        jobsTable,
        {
          ..._leaseReleaseFields(now),
          'status': EnrichmentJobStatus.retryScheduled.name,
          'failure_kind': failureKind,
          'last_error': error,
          'retry_count': nextRetryCount,
          'next_attempt_at': nextAttemptAt.millisecondsSinceEpoch,
        },
        where: 'deck_id = ? AND lease_owner = ?',
        whereArgs: [deckId, owner],
      );
    });
  }

  /// Estimated delay before a `retryScheduled` job should be retried, purely
  /// for the [DeckEnrichmentState.paused] display and its refresh timers (see
  /// `InatEnrichmentQueueService._syncPauseDisplayTimers`). Does not gate
  /// `claimNextJob` — actual request pacing happens in the HTTP layer via
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

  Future<void> markStageFailedPermanent({
    required String deckId,
    required EnrichmentStage stage,
    required String owner,
    required String error,
    required String failureKind,
  }) async {
    final db = await _db;
    final now = DateTime.now();
    _log.debug(
      'Mark stage permanent failure deck=$deckId stage=${stage.name} '
      'owner=$owner kind=$failureKind error=$error',
    );
    await db.transaction((txn) async {
      final job = await _loadJobLeasedBy(txn, deckId, owner);
      if (job == null) return;
      await _upsertStage(txn, deckId, stage, EnrichmentStageState.failed, now);
      await txn.update(
        jobsTable,
        {
          ..._leaseReleaseFields(now),
          'status': EnrichmentJobStatus.failedPermanent.name,
          'failure_kind': failureKind,
          'last_error': error,
          'progress_completed': 0,
          'progress_total': 0,
          'retry_count': 0,
          'next_attempt_at': null,
        },
        where: 'deck_id = ? AND lease_owner = ?',
        whereArgs: [deckId, owner],
      );
    });
  }

  Future<void> pauseJobsOwnedBy(String owner) async {
    final db = await _db;
    final now = DateTime.now();
    _log.debug('Pause jobs owned by $owner');
    await db.transaction((txn) async {
      final jobs = await txn.query(
        jobsTable,
        where: 'lease_owner = ?',
        whereArgs: [owner],
      );
      for (final row in jobs) {
        final deckId = row['deck_id'] as String;
        final stageRows = await txn.query(
          stagesTable,
          where: 'deck_id = ?',
          whereArgs: [deckId],
        );
        for (final stageRow in stageRows) {
          if ((stageRow['state'] as String) ==
              EnrichmentStageState.running.name) {
            await txn.update(
              stagesTable,
              {
                'state': EnrichmentStageState.pending.name,
                'updated_at': now.millisecondsSinceEpoch,
              },
              where: 'deck_id = ? AND stage = ?',
              whereArgs: [deckId, stageRow['stage']],
            );
          }
        }
        await txn.update(
          jobsTable,
          {
            'status': EnrichmentJobStatus.pausedBySystem.name,
            'current_stage': null,
            'lease_owner': null,
            'lease_expires_at': null,
            'updated_at': now.millisecondsSinceEpoch,
          },
          where: 'deck_id = ?',
          whereArgs: [deckId],
        );
        _log.debug('Paused job deck=$deckId owner=$owner');
      }
    });
  }

  EnrichmentStage? nextRunnableStage(EnrichmentJobRecord job) =>
      _nextRunnableStage(job);

  /// Clear the persisted `next_attempt_at` for all jobs currently in
  /// `retryScheduled` status. Called when the host cooldown ends so that
  /// `claimNextJob` picks the jobs up immediately instead of waiting for the
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

  Future<List<EnrichmentJobRecord>> _loadAllJobsBatched(
    DatabaseExecutor executor,
  ) async {
    final jobRows = await executor.query(jobsTable, orderBy: 'updated_at ASC');
    if (jobRows.isEmpty) return const [];
    final allStageRows = await executor.query(stagesTable);
    final stagesByDeck = <String, List<Map<String, dynamic>>>{};
    for (final row in allStageRows) {
      final deckId = row['deck_id'] as String;
      (stagesByDeck[deckId] ??= []).add(row);
    }
    return [
      for (final row in jobRows)
        _buildRecordFromRow(
          row,
          stagesByDeck[row['deck_id'] as String] ?? const [],
        ),
    ];
  }

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
    final stageRows = await executor.query(
      stagesTable,
      where: 'deck_id = ?',
      whereArgs: [deckId],
    );
    return _buildRecordFromRow(rows.first, stageRows);
  }

  EnrichmentJobRecord _buildRecordFromRow(
    Map<String, dynamic> row,
    List<Map<String, dynamic>> stageRows,
  ) {
    final deckId = row['deck_id'] as String;
    final payloadJson = row['payload_json'] as String? ?? '{}';
    final stageStates = {
      for (final stage in EnrichmentStage.values)
        stage: EnrichmentStageState.skipped,
    };
    for (final stageRow in stageRows) {
      final stage = EnrichmentStage.values.byName(stageRow['stage'] as String);
      stageStates[stage] = EnrichmentStageState.values.byName(
        stageRow['state'] as String,
      );
    }
    return EnrichmentJobRecord(
      deckId: deckId,
      status: EnrichmentJobStatus.values.byName(row['status'] as String),
      attemptedAt: _millisToDateTime(row['attempted_at'] as int?),
      completedAt: _millisToDateTime(row['completed_at'] as int?),
      currentStage: row['current_stage'] == null
          ? null
          : EnrichmentStage.values.byName(row['current_stage'] as String),
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
      stageStates: stageStates,
    );
  }

  /// Loads the job for [deckId] and returns it only if it's still owned by
  /// [owner] and not cancelled — the guard every `markStage*` mutation needs
  /// before touching a job it claimed a lease on. Returns null (meaning
  /// "nothing to do") if the job was cancelled or its lease moved on from
  /// under us.
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

  /// The fields every `markStage*` mutation resets identically: the lease is
  /// released and `current_stage`/`updated_at` are refreshed. Callers spread
  /// this and override/add whatever else is specific to that outcome.
  Map<String, dynamic> _leaseReleaseFields(DateTime now) => {
    'current_stage': null,
    'lease_owner': null,
    'lease_expires_at': null,
    'updated_at': now.millisecondsSinceEpoch,
  };

  Future<void> _upsertStage(
    DatabaseExecutor executor,
    String deckId,
    EnrichmentStage stage,
    EnrichmentStageState state,
    DateTime now,
  ) async {
    await executor.insert(stagesTable, {
      'deck_id': deckId,
      'stage': stage.name,
      'state': state.name,
      'updated_at': now.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _recoverExpiredLeases(
    DatabaseExecutor executor,
    DateTime now,
  ) async {
    final expiredJobs = await executor.query(
      jobsTable,
      columns: ['deck_id'],
      where: 'lease_expires_at IS NOT NULL AND lease_expires_at < ?',
      whereArgs: [now.millisecondsSinceEpoch],
    );
    for (final row in expiredJobs) {
      final deckId = row['deck_id'] as String;
      _log.debug('Recover expired lease deck=$deckId');
      await executor.update(
        stagesTable,
        {
          'state': EnrichmentStageState.pending.name,
          'updated_at': now.millisecondsSinceEpoch,
        },
        where: 'deck_id = ? AND state = ?',
        whereArgs: [deckId, EnrichmentStageState.running.name],
      );
      await executor.update(
        jobsTable,
        {
          'status': EnrichmentJobStatus.pausedBySystem.name,
          'current_stage': null,
          'lease_owner': null,
          'lease_expires_at': null,
          'updated_at': now.millisecondsSinceEpoch,
        },
        where: 'deck_id = ?',
        whereArgs: [deckId],
      );
    }
  }

  EnrichmentStage? _nextRunnableStage(EnrichmentJobRecord job) {
    if (_isPending(job, EnrichmentStage.cover)) {
      return EnrichmentStage.cover;
    }
    return null;
  }

  bool _isPending(EnrichmentJobRecord job, EnrichmentStage stage) =>
      job.stageStates[stage] == EnrichmentStageState.pending;

  static DateTime? _millisToDateTime(int? millis) =>
      millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);

  static String? _normalizeNullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
