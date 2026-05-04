import 'package:discere/enrichment/repository/enrichment_job_repository.dart';
import 'package:discere/shared/model/enrichment_progress_status.dart';
export 'package:discere/shared/model/enrichment_progress_status.dart';

INatEnrichmentPhase? phaseForEnrichmentStage(EnrichmentStage? stage) {
  return switch (stage) {
    EnrichmentStage.nameResolution => INatEnrichmentPhase.nameResolution,
    EnrichmentStage.cover => INatEnrichmentPhase.cover,
    EnrichmentStage.base => INatEnrichmentPhase.base,
    EnrichmentStage.inatPrimary ||
    EnrichmentStage.inatBackfill => INatEnrichmentPhase.inat,
    EnrichmentStage.names => INatEnrichmentPhase.names,
    null => null,
  };
}

INatEnrichmentStatus deriveEnrichmentStatus(
  List<EnrichmentJobRecord> jobs, {
  bool hasActiveHostCooldown = false,
  bool preferBackgroundMessaging = false,
}) {
  final pendingJobs = jobs.where((job) => job.hasPendingWork).toList();
  if (pendingJobs.isEmpty) return INatEnrichmentStatus.idle;
  final visibleJobs = jobs
      .where((job) => job.status != EnrichmentJobStatus.cancelled)
      .toList();
  final readyDeckCount = visibleJobs.where(isQuickPassReadyForJob).length;

  final runningJobs = jobs.where((job) {
    return job.status == EnrichmentJobStatus.runningForeground ||
        job.status == EnrichmentJobStatus.runningBackground;
  }).toList();

  // Jobs that are actively working or queued to run imminently — excludes
  // retryScheduled and failedTemporary which may wait hours before running.
  final immediatePendingJobs = pendingJobs.where((job) {
    return job.status == EnrichmentJobStatus.queued ||
        job.status == EnrichmentJobStatus.runningForeground ||
        job.status == EnrichmentJobStatus.runningBackground ||
        job.status == EnrichmentJobStatus.pausedBySystem;
  }).toList();

  final activeJobs = runningJobs.isNotEmpty ? runningJobs : pendingJobs;
  activeJobs.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  final activeJob = activeJobs.first;
  final activeStage =
      activeJob.currentStage ??
      EnrichmentJobRepository().nextRunnableStage(activeJob);
  final progress = deriveDisplayedProgress(activeJob, stage: activeStage);
  return INatEnrichmentStatus(
    isRunning: runningJobs.isNotEmpty,
    hasPendingWork: true,
    hasActiveWork: immediatePendingJobs.isNotEmpty,
    hasActiveHostCooldown: hasActiveHostCooldown,
    preferBackgroundMessaging: preferBackgroundMessaging,
    nextAttemptAt: activeJob.nextAttemptAt,
    phase: phaseForEnrichmentStage(activeStage) ?? INatEnrichmentPhase.base,
    completed: progress.completed,
    total: progress.total,
    activeDeckCount: pendingJobs.length,
    readyDeckCount: readyDeckCount,
    totalDeckCount: visibleJobs.length,
  );
}

({int completed, int total}) deriveDisplayedProgress(
  EnrichmentJobRecord job, {
  EnrichmentStage? stage,
}) {
  if (job.progressTotal > 0) {
    return (completed: job.progressCompleted, total: job.progressTotal);
  }

  final effectiveStage =
      stage ??
      job.currentStage ??
      EnrichmentJobRepository().nextRunnableStage(job);
  if (effectiveStage == null) {
    return (completed: job.progressCompleted, total: job.progressTotal);
  }

  return switch (effectiveStage) {
    EnrichmentStage.nameResolution => (
      completed: 0,
      total: job.payload.unresolvedSpeciesNames.length,
    ),
    EnrichmentStage.cover => (
      completed: 0,
      total: job.payload.coverImageUrl?.trim().isNotEmpty ?? false ? 1 : 0,
    ),
    EnrichmentStage.base ||
    EnrichmentStage.inatPrimary ||
    EnrichmentStage.names ||
    EnrichmentStage.inatBackfill => _deriveSpeciesStageProgress(
      job,
      effectiveStage,
    ),
  };
}

({int completed, int total}) _deriveSpeciesStageProgress(
  EnrichmentJobRecord job,
  EnrichmentStage stage,
) {
  final total = job.payload.speciesIds.length;
  final remaining = job.payload.remainingSpeciesIdsForStage(stage);
  if (remaining == null) {
    return (completed: 0, total: total);
  }
  final completed = total - remaining.toSet().length;
  return (completed: completed < 0 ? 0 : completed, total: total);
}

bool isQuickPassReadyForJob(EnrichmentJobRecord job) {
  for (final stage in _quickPassStages(job)) {
    final state = job.stageStates[stage];
    if (state != EnrichmentStageState.succeeded &&
        state != EnrichmentStageState.skipped) {
      return false;
    }
  }
  return true;
}

Iterable<EnrichmentStage> _quickPassStages(EnrichmentJobRecord job) sync* {
  if (job.payload.unresolvedSpeciesNames.isNotEmpty) {
    yield EnrichmentStage.nameResolution;
  }
  if ((job.payload.coverImageUrl?.trim().isNotEmpty ?? false)) {
    yield EnrichmentStage.cover;
  }
  yield EnrichmentStage.base;
}
