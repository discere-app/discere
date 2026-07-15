import 'dart:convert';


import 'package:discere/shared/persistence/database_helper.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:sqflite/sqflite.dart';

enum EnrichmentJobStatus {
  queued,
  runningForeground,
  runningBackground,
  pausedBySystem,
  retryScheduled,
  cancelled,
  completed,
  failedTemporary,
  failedPermanent,
}

enum EnrichmentStage {
  nameResolution,
  cover,
  base,
  inatPrimary,
  names,
  inatBackfill,
}

enum EnrichmentStageState { pending, running, succeeded, failed, skipped }

enum EnrichmentRunnerKind { foreground, background }

class EnrichmentJobPayload {
  final List<String> speciesIds;
  final String? coverImageUrl;
  final bool includeINatPhotos;
  final bool includeCommonNames;
  final List<String> unresolvedSpeciesNames;
  final List<String> stillUnresolvedNames;
  final Map<String, List<String>> remainingSpeciesIdsByStage;
  final Map<String, List<String>> remainingTaxonomyEntityKeysByStage;
  final bool hasAnyImage;

  const EnrichmentJobPayload({
    this.speciesIds = const [],
    this.coverImageUrl,
    this.includeINatPhotos = true,
    this.includeCommonNames = true,
    this.unresolvedSpeciesNames = const [],
    this.stillUnresolvedNames = const [],
    this.remainingSpeciesIdsByStage = const {},
    this.remainingTaxonomyEntityKeysByStage = const {},
    this.hasAnyImage = false,
  });

  Map<String, dynamic> toJson() => {
    'speciesIds': speciesIds,
    'coverImageUrl': coverImageUrl,
    'includeINatPhotos': includeINatPhotos,
    'includeCommonNames': includeCommonNames,
    'unresolvedSpeciesNames': unresolvedSpeciesNames,
    'stillUnresolvedNames': stillUnresolvedNames,
    'remainingSpeciesIdsByStage': remainingSpeciesIdsByStage,
    'remainingTaxonomyEntityKeysByStage': remainingTaxonomyEntityKeysByStage,
    'hasAnyImage': hasAnyImage,
  };

  factory EnrichmentJobPayload.fromJson(Map<String, dynamic> json) {
    return EnrichmentJobPayload(
      speciesIds: (json['speciesIds'] as List<dynamic>? ?? const [])
          .cast<String>(),
      coverImageUrl: json['coverImageUrl'] as String?,
      includeINatPhotos: json['includeINatPhotos'] as bool? ?? true,
      includeCommonNames: json['includeCommonNames'] as bool? ?? true,
      unresolvedSpeciesNames:
          (json['unresolvedSpeciesNames'] as List<dynamic>? ?? const [])
              .cast<String>(),
      stillUnresolvedNames:
          (json['stillUnresolvedNames'] as List<dynamic>? ?? const [])
              .cast<String>(),
      remainingSpeciesIdsByStage: {
        for (final entry
            in (json['remainingSpeciesIdsByStage'] as Map<String, dynamic>? ??
                    const <String, dynamic>{})
                .entries)
          entry.key: (entry.value as List<dynamic>? ?? const []).cast<String>(),
      },
      remainingTaxonomyEntityKeysByStage: {
        for (final entry
            in (json['remainingTaxonomyEntityKeysByStage']
                        as Map<String, dynamic>? ??
                    const <String, dynamic>{})
                .entries)
          entry.key: (entry.value as List<dynamic>? ?? const []).cast<String>(),
      },
      hasAnyImage: json['hasAnyImage'] as bool? ?? false,
    );
  }

  EnrichmentJobPayload copyWith({
    List<String>? speciesIds,
    String? coverImageUrl,
    bool? includeINatPhotos,
    bool? includeCommonNames,
    List<String>? unresolvedSpeciesNames,
    List<String>? stillUnresolvedNames,
    Map<String, List<String>>? remainingSpeciesIdsByStage,
    Map<String, List<String>>? remainingTaxonomyEntityKeysByStage,
    bool? hasAnyImage,
  }) {
    return EnrichmentJobPayload(
      speciesIds: speciesIds ?? this.speciesIds,
      coverImageUrl: coverImageUrl ?? this.coverImageUrl,
      includeINatPhotos: includeINatPhotos ?? this.includeINatPhotos,
      includeCommonNames: includeCommonNames ?? this.includeCommonNames,
      unresolvedSpeciesNames:
          unresolvedSpeciesNames ?? this.unresolvedSpeciesNames,
      stillUnresolvedNames: stillUnresolvedNames ?? this.stillUnresolvedNames,
      remainingSpeciesIdsByStage:
          remainingSpeciesIdsByStage ?? this.remainingSpeciesIdsByStage,
      remainingTaxonomyEntityKeysByStage:
          remainingTaxonomyEntityKeysByStage ??
          this.remainingTaxonomyEntityKeysByStage,
      hasAnyImage: hasAnyImage ?? this.hasAnyImage,
    );
  }

  List<String>? remainingSpeciesIdsForStage(EnrichmentStage stage) {
    return remainingSpeciesIdsByStage[stage.name];
  }

  List<String>? remainingTaxonomyEntityKeysForStage(EnrichmentStage stage) {
    return remainingTaxonomyEntityKeysByStage[stage.name];
  }

  EnrichmentJobPayload copyWithRemainingSpeciesIds(
    EnrichmentStage stage,
    Iterable<String>? speciesIds,
  ) {
    final next = Map<String, List<String>>.from(remainingSpeciesIdsByStage);
    if (speciesIds == null) {
      next.remove(stage.name);
    } else {
      next[stage.name] = speciesIds.toList();
    }
    return copyWith(remainingSpeciesIdsByStage: next);
  }

  EnrichmentJobPayload copyWithRemainingTaxonomyEntityKeys(
    EnrichmentStage stage,
    Iterable<String>? entityKeys,
  ) {
    final next = Map<String, List<String>>.from(
      remainingTaxonomyEntityKeysByStage,
    );
    if (entityKeys == null) {
      next.remove(stage.name);
    } else {
      next[stage.name] = entityKeys.toList();
    }
    return copyWith(remainingTaxonomyEntityKeysByStage: next);
  }
}

class EnrichmentJobRecord {
  final String deckId;
  final EnrichmentJobStatus status;
  final DateTime? attemptedAt;
  final DateTime? completedAt;
  final EnrichmentStage? currentStage;
  final EnrichmentJobPayload payload;
  final String? failureKind;
  final String? lastError;
  final int progressCompleted;
  final int progressTotal;
  final int retryCount;
  final DateTime? nextAttemptAt;
  final String? leaseOwner;
  final DateTime? leaseExpiresAt;
  final DateTime updatedAt;
  final Map<EnrichmentStage, EnrichmentStageState> stageStates;

  const EnrichmentJobRecord({
    required this.deckId,
    required this.status,
    required this.attemptedAt,
    required this.completedAt,
    required this.currentStage,
    required this.payload,
    required this.failureKind,
    required this.lastError,
    required this.progressCompleted,
    required this.progressTotal,
    required this.retryCount,
    required this.nextAttemptAt,
    required this.leaseOwner,
    required this.leaseExpiresAt,
    required this.updatedAt,
    required this.stageStates,
  });

  bool get hasPendingWork {
    if (status == EnrichmentJobStatus.cancelled ||
        status == EnrichmentJobStatus.completed ||
        status == EnrichmentJobStatus.failedPermanent) {
      return false;
    }
    return stageStates.values.any(
          (state) => state == EnrichmentStageState.pending,
        ) ||
        stageStates.values.any(
          (state) => state == EnrichmentStageState.running,
        );
  }

  /// True once both image-loading stages (`base` and `inatPrimary`) have
  /// reached a terminal-success state (`succeeded` or `skipped`) for every
  /// species. From this point on the deck has at least one image — or an
  /// explicit no-result marker — for every card and is learnable.
  bool get everySpeciesHasImage {
    bool isFinal(EnrichmentStageState? state) =>
        state == EnrichmentStageState.succeeded ||
        state == EnrichmentStageState.skipped;
    return isFinal(stageStates[EnrichmentStage.base]) &&
        isFinal(stageStates[EnrichmentStage.inatPrimary]);
  }
}

class EnrichmentJobRepository {
  static final _log = Logger.forType(EnrichmentJobRepository);
  static const jobsTable = 'enrichment_jobs';
  static const stagesTable = 'enrichment_job_stages';

  final Database? _injectedDb;

  const EnrichmentJobRepository([this._injectedDb]);

  Future<Database> get _db async => _injectedDb ?? DatabaseHelper.userDb;

  Future<void> scheduleDeckJob({
    required String deckId,
    required Iterable<String> speciesIds,
    required bool includeINatPhotos,
    required bool includeCommonNames,
    String? coverImageUrl,
    List<String> unresolvedSpeciesNames = const [],
  }) async {
    final db = await _db;
    final now = DateTime.now();
    final orderedSpeciesIds = _orderedUniqueSpeciesIds(speciesIds);
    _log.debug(
      'Schedule job deck=$deckId species=${orderedSpeciesIds.length} '
      'unresolved=${unresolvedSpeciesNames.length} '
      'includeINat=$includeINatPhotos includeNames=$includeCommonNames '
      'cover=${_normalizeNullable(coverImageUrl) != null}',
    );

    await db.transaction((txn) async {
      final existing = await _loadJob(txn, deckId);
      final payload = (existing?.payload ?? const EnrichmentJobPayload())
          .copyWith(
            coverImageUrl:
                _normalizeNullable(coverImageUrl) ??
                existing?.payload.coverImageUrl,
            speciesIds: orderedSpeciesIds,
            includeINatPhotos: includeINatPhotos,
            includeCommonNames: includeCommonNames,
            unresolvedSpeciesNames: unresolvedSpeciesNames,
            stillUnresolvedNames: const [],
            remainingSpeciesIdsByStage: const {},
            remainingTaxonomyEntityKeysByStage: const {},
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
      await _upsertStage(
        txn,
        deckId,
        EnrichmentStage.base,
        EnrichmentStageState.pending,
        now,
      );
      await _upsertStage(
        txn,
        deckId,
        EnrichmentStage.nameResolution,
        payload.unresolvedSpeciesNames.isEmpty
            ? EnrichmentStageState.skipped
            : EnrichmentStageState.pending,
        now,
      );
      final iNatState = includeINatPhotos
          ? EnrichmentStageState.pending
          : EnrichmentStageState.skipped;
      await _upsertStage(
        txn,
        deckId,
        EnrichmentStage.inatPrimary,
        iNatState,
        now,
      );
      await _upsertStage(
        txn,
        deckId,
        EnrichmentStage.inatBackfill,
        iNatState,
        now,
      );
      await _upsertStage(
        txn,
        deckId,
        EnrichmentStage.names,
        includeCommonNames
            ? EnrichmentStageState.pending
            : EnrichmentStageState.skipped,
        now,
      );
    });
  }

  static List<String> _orderedUniqueSpeciesIds(Iterable<String> speciesIds) {
    final ordered = <String>[];
    final seen = <String>{};
    for (final speciesId in speciesIds) {
      final normalized = speciesId.trim();
      if (normalized.isEmpty || !seen.add(normalized)) {
        continue;
      }
      ordered.add(normalized);
    }
    return ordered;
  }

  Future<void> cancelDeckJob(String deckId) async {
    final db = await _db;
    _log.debug('Cancel job deck=$deckId');
    await db.transaction((txn) async {
      final now = DateTime.now();
      await txn.update(
        stagesTable,
        {
          'state': EnrichmentStageState.skipped.name,
          'updated_at': now.millisecondsSinceEpoch,
        },
        where: 'deck_id = ? AND state IN (?, ?)',
        whereArgs: [
          deckId,
          EnrichmentStageState.pending.name,
          EnrichmentStageState.running.name,
        ],
      );
      await txn.update(
        jobsTable,
        {
          'status': EnrichmentJobStatus.cancelled.name,
          'current_stage': null,
          'last_error': null,
          'failure_kind': null,
          'progress_completed': 0,
          'progress_total': 0,
          'retry_count': 0,
          'next_attempt_at': null,
          'lease_owner': null,
          'lease_expires_at': null,
          'updated_at': now.millisecondsSinceEpoch,
        },
        where: 'deck_id = ?',
        whereArgs: [deckId],
      );
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
    return _loadAllJobs(db);
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
      var selectedPriority = 1 << 30;
      for (final job in jobs) {
        if (!job.hasPendingWork) continue;
        if (job.leaseOwner != null && job.leaseOwner != owner) continue;
        final nextStage = _nextRunnableStage(job);
        if (nextStage == null) continue;
        final priority = _stagePriority(nextStage);
        if (selectedJob == null ||
            priority < selectedPriority ||
            (priority == selectedPriority &&
                job.updatedAt.isBefore(selectedJob.updatedAt)) ||
            (priority == selectedPriority &&
                job.updatedAt.isAtSameMomentAs(selectedJob.updatedAt) &&
                job.deckId.compareTo(selectedJob.deckId) < 0)) {
          selectedJob = job;
          selectedStage = nextStage;
          selectedPriority = priority;
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
          'stage=${selectedStage.name} species=${selectedJob.payload.speciesIds.length} '
          'unresolved=${selectedJob.payload.unresolvedSpeciesNames.length} '
          'priority=$selectedPriority',
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
    required int progressCompleted,
    required int progressTotal,
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
          'progress_completed': progressCompleted,
          'progress_total': progressTotal,
          'next_attempt_at': null,
          'lease_owner': owner,
          'updated_at': now.millisecondsSinceEpoch,
        },
        where: 'deck_id = ?',
        whereArgs: [deckId],
      );
    });
  }

  Future<void> updateProgress({
    required String deckId,
    required int completed,
    required int total,
  }) async {
    final db = await _db;
    await db.update(
      jobsTable,
      {
        'progress_completed': completed,
        'progress_total': total,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'deck_id = ?',
      whereArgs: [deckId],
    );
  }

  Future<void> updateStageCheckpoint({
    required String deckId,
    required String owner,
    required EnrichmentJobPayload payload,
    required int completed,
    required int total,
  }) async {
    final db = await _db;
    await db.update(
      jobsTable,
      {
        'payload_json': jsonEncode(payload.toJson()),
        'progress_completed': completed,
        'progress_total': total,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'deck_id = ? AND lease_owner = ?',
      whereArgs: [deckId, owner],
    );
  }

  Future<void> markStageYielded({
    required String deckId,
    required EnrichmentStage stage,
    required String owner,
    required EnrichmentJobPayload payload,
    required int completed,
    required int total,
  }) async {
    final db = await _db;
    final now = DateTime.now();
    _log.debug(
      'Mark stage yielded deck=$deckId stage=${stage.name} owner=$owner '
      'completed=$completed total=$total',
    );
    await db.transaction((txn) async {
      final job = await _loadJob(txn, deckId);
      if (job == null ||
          job.status == EnrichmentJobStatus.cancelled ||
          job.leaseOwner != owner) {
        return;
      }
      await _upsertStage(txn, deckId, stage, EnrichmentStageState.pending, now);
      await txn.update(
        jobsTable,
        {
          'status': EnrichmentJobStatus.queued.name,
          'current_stage': null,
          'payload_json': jsonEncode(payload.toJson()),
          'failure_kind': null,
          'last_error': null,
          'progress_completed': completed,
          'progress_total': total,
          'retry_count': 0,
          'next_attempt_at': null,
          'lease_owner': null,
          'lease_expires_at': null,
          'updated_at': now.millisecondsSinceEpoch,
        },
        where: 'deck_id = ? AND lease_owner = ?',
        whereArgs: [deckId, owner],
      );
    });
  }

  Future<void> markStageSucceeded({
    required String deckId,
    required EnrichmentStage stage,
    required String owner,
    EnrichmentJobPayload? payload,
  }) async {
    final db = await _db;
    await db.transaction((txn) async {
      final now = DateTime.now();
      final job = await _loadJob(txn, deckId);
      if (job == null ||
          job.status == EnrichmentJobStatus.cancelled ||
          job.leaseOwner != owner) {
        return;
      }
      await _upsertStage(
        txn,
        deckId,
        stage,
        EnrichmentStageState.succeeded,
        now,
      );
      final nextPayload = (payload ?? job.payload).copyWithRemainingSpeciesIds(
        stage,
        null,
      );
      final stageStates = Map<EnrichmentStage, EnrichmentStageState>.from(
        job.stageStates,
      )..[stage] = EnrichmentStageState.succeeded;
      final isCompleted =
          _nextRunnableStage(
                EnrichmentJobRecord(
                  deckId: job.deckId,
                  status: job.status,
                  attemptedAt: job.attemptedAt,
                  completedAt: job.completedAt,
                  currentStage: job.currentStage,
                  payload: nextPayload,
                  failureKind: job.failureKind,
                  lastError: job.lastError,
                  progressCompleted: job.progressCompleted,
                  progressTotal: job.progressTotal,
                  retryCount: job.retryCount,
                  nextAttemptAt: job.nextAttemptAt,
                  leaseOwner: job.leaseOwner,
                  leaseExpiresAt: job.leaseExpiresAt,
                  updatedAt: job.updatedAt,
                  stageStates: stageStates,
                ),
              ) ==
              null &&
          !stageStates.values.contains(EnrichmentStageState.failed);

      await txn.update(
        jobsTable,
        {
          'status': isCompleted
              ? EnrichmentJobStatus.completed.name
              : EnrichmentJobStatus.queued.name,
          'completed_at': isCompleted ? now.millisecondsSinceEpoch : null,
          'current_stage': null,
          'payload_json': jsonEncode(nextPayload.toJson()),
          'failure_kind': null,
          'last_error': null,
          'progress_completed': 0,
          'progress_total': 0,
          'retry_count': 0,
          'next_attempt_at': null,
          'lease_owner': null,
          'lease_expires_at': null,
          'updated_at': now.millisecondsSinceEpoch,
        },
        where: 'deck_id = ? AND lease_owner = ?',
        whereArgs: [deckId, owner],
      );
      _log.debug(
        'Mark stage succeeded deck=$deckId stage=${stage.name} owner=$owner '
        'completed=$isCompleted species=${nextPayload.speciesIds.length} '
        'stillUnresolved=${nextPayload.stillUnresolvedNames.length}',
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
      final job = await _loadJob(txn, deckId);
      if (job == null ||
          job.status == EnrichmentJobStatus.cancelled ||
          job.leaseOwner != owner) {
        return;
      }
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
          'status': EnrichmentJobStatus.retryScheduled.name,
          'current_stage': null,
          'failure_kind': failureKind,
          'last_error': error,
          'progress_completed': job.progressCompleted,
          'progress_total': job.progressTotal,
          'retry_count': nextRetryCount,
          'next_attempt_at': nextAttemptAt.millisecondsSinceEpoch,
          'lease_owner': null,
          'lease_expires_at': null,
          'updated_at': now.millisecondsSinceEpoch,
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
      final job = await _loadJob(txn, deckId);
      if (job == null ||
          job.status == EnrichmentJobStatus.cancelled ||
          job.leaseOwner != owner) {
        return;
      }
      await _upsertStage(txn, deckId, stage, EnrichmentStageState.failed, now);
      await txn.update(
        jobsTable,
        {
          'status': EnrichmentJobStatus.failedPermanent.name,
          'current_stage': null,
          'failure_kind': failureKind,
          'last_error': error,
          'progress_completed': 0,
          'progress_total': 0,
          'retry_count': 0,
          'next_attempt_at': null,
          'lease_owner': null,
          'lease_expires_at': null,
          'updated_at': now.millisecondsSinceEpoch,
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

  Future<List<EnrichmentJobRecord>> _loadAllJobs(
    DatabaseExecutor executor,
  ) => _loadAllJobsBatched(executor);

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
        _buildRecordFromRow(row, stagesByDeck[row['deck_id'] as String] ?? const []),
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
    if (_isPending(job, EnrichmentStage.cover) &&
        _normalizeNullable(job.payload.coverImageUrl) != null) {
      return EnrichmentStage.cover;
    }
    if (_isPending(job, EnrichmentStage.nameResolution) &&
        job.payload.unresolvedSpeciesNames.isNotEmpty) {
      return EnrichmentStage.nameResolution;
    }
    if (_isPending(job, EnrichmentStage.base)) {
      return EnrichmentStage.base;
    }
    if (_isPending(job, EnrichmentStage.inatPrimary) &&
        job.payload.includeINatPhotos) {
      return EnrichmentStage.inatPrimary;
    }
    if (_isPending(job, EnrichmentStage.names) &&
        job.payload.includeCommonNames) {
      return EnrichmentStage.names;
    }
    if (_isPending(job, EnrichmentStage.inatBackfill) &&
        job.payload.includeINatPhotos &&
        !_isPending(job, EnrichmentStage.inatPrimary) &&
        !_isRunning(job, EnrichmentStage.inatPrimary)) {
      return EnrichmentStage.inatBackfill;
    }
    return null;
  }

  bool _isPending(EnrichmentJobRecord job, EnrichmentStage stage) =>
      job.stageStates[stage] == EnrichmentStageState.pending;

  bool _isRunning(EnrichmentJobRecord job, EnrichmentStage stage) =>
      job.stageStates[stage] == EnrichmentStageState.running;

  int _stagePriority(EnrichmentStage stage) {
    return switch (stage) {
      EnrichmentStage.cover => 0,
      EnrichmentStage.nameResolution => 1,
      EnrichmentStage.base => 2,
      EnrichmentStage.inatPrimary => 3,
      EnrichmentStage.names => 4,
      EnrichmentStage.inatBackfill => 5,
    };
  }

  static DateTime? _millisToDateTime(int? millis) =>
      millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);

  static String? _normalizeNullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
