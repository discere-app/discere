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

INatEnrichmentStatus deriveEnrichmentStatus(List<EnrichmentJobRecord> jobs) {
  final runningJobs = jobs.where((job) {
    return job.status == EnrichmentJobStatus.runningForeground ||
        job.status == EnrichmentJobStatus.runningBackground;
  }).toList();
  if (runningJobs.isEmpty) return INatEnrichmentStatus.idle;

  final activeJob = runningJobs.first;
  return INatEnrichmentStatus(
    isRunning: true,
    phase: phaseForEnrichmentStage(activeJob.currentStage) ??
        INatEnrichmentPhase.base,
    completed: activeJob.progressCompleted,
    total: activeJob.progressTotal,
    activeDeckCount: runningJobs.length,
  );
}
