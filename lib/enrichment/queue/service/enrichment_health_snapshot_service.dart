import 'package:discere/enrichment/pipeline/model/enrichment_work_state_count.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_repository.dart';
import 'package:discere/enrichment/queue/repository/enrichment_job_repository.dart';

class EnrichmentHealthSnapshot {
  final List<EnrichmentWorkStateCount> workStateCounts;
  final List<EnrichmentJobRecord> coverJobs;

  const EnrichmentHealthSnapshot({
    required this.workStateCounts,
    required this.coverJobs,
  });
}

/// Live, read-only view of what the producer-consumer enrichment pipeline
/// currently has outstanding — replaces trying to reconstruct job/run status
/// after the fact from an event log (see `docs/enrichment.md` for the
/// pipeline architecture this reads from).
class EnrichmentHealthSnapshotService {
  final EnrichmentWorkRepository _workRepository;
  final EnrichmentJobRepository _jobRepository;

  const EnrichmentHealthSnapshotService({
    EnrichmentWorkRepository workRepository = const EnrichmentWorkRepository(),
    EnrichmentJobRepository jobRepository = const EnrichmentJobRepository(),
  }) : _workRepository = workRepository,
       _jobRepository = jobRepository;

  Future<EnrichmentHealthSnapshot> loadSnapshot() async {
    final results = await Future.wait([
      _workRepository.loadCapabilityStateCounts(),
      _workRepository.loadTaxonomyWorkStateCounts(),
      _workRepository.loadUnresolvedNamesStateCounts(),
      _jobRepository.loadAllJobs(),
    ]);
    final workStateCounts = [
      ...results[0] as List<EnrichmentWorkStateCount>,
      ...results[1] as List<EnrichmentWorkStateCount>,
      ...results[2] as List<EnrichmentWorkStateCount>,
    ];
    return EnrichmentHealthSnapshot(
      workStateCounts: workStateCounts,
      coverJobs: results[3] as List<EnrichmentJobRecord>,
    );
  }

  /// Manually triggers the same stuck-lease/interrupted-work recovery the
  /// pipeline already runs automatically on every claim cycle / app start —
  /// for the diagnostics page's "reset stuck jobs" action, so a user doesn't
  /// have to wait for the next natural cycle. Returns the number of cover
  /// jobs whose lease was recovered.
  Future<int> recoverStuckWork() async {
    final recoveredJobs = await _jobRepository.recoverExpiredLeases();
    await _workRepository.recoverInterruptedWork();
    return recoveredJobs;
  }
}
