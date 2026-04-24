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
  final activeJobs = runningJobs.isNotEmpty ? runningJobs : pendingJobs;
  activeJobs.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  final activeJob = activeJobs.first;
  final activeStage =
      activeJob.currentStage ??
      EnrichmentJobRepository().nextRunnableStage(activeJob);
  return INatEnrichmentStatus(
    isRunning: runningJobs.isNotEmpty,
    hasPendingWork: true,
    hasActiveHostCooldown: hasActiveHostCooldown,
    phase: phaseForEnrichmentStage(activeStage) ?? INatEnrichmentPhase.base,
    completed: activeJob.progressCompleted,
    total: activeJob.progressTotal,
    activeDeckCount: pendingJobs.length,
    readyDeckCount: readyDeckCount,
    totalDeckCount: visibleJobs.length,
  );
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
