import 'package:discere/enrichment/pipeline/repository/enrichment_ownership_repository.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_maintenance_repository.dart';
import 'package:discere/enrichment/ports/enrichment_job_ports.dart';
import 'package:discere/enrichment/queue/repository/enrichment_job_repository.dart';
import 'package:discere/shared/persistence/closed_database_tolerance.dart';
import 'package:discere/shared/util/logger.dart';

/// The enrichment queue's repairs at startup, before its first refresh.
///
/// Both are best effort. A failure is logged with its stack trace and the
/// queue starts anyway: a repair that did not land is attempted again on the
/// next start, while refusing to start would leave every deck without
/// enrichment for the sake of a few stranded rows. A database closed
/// underneath a repair drops it quietly.
class EnrichmentStartupMaintenance {
  static final _log = Logger.forType(EnrichmentStartupMaintenance);

  final EnrichmentWorkMaintenanceRepository _maintenanceRepository;
  final EnrichmentJobRepository _jobRepository;
  final EnrichmentOwnershipRepository _ownershipRepository;
  final AllDeckIdsPort? _allDeckIdsPort;

  const EnrichmentStartupMaintenance({
    required EnrichmentWorkMaintenanceRepository maintenanceRepository,
    required EnrichmentJobRepository jobRepository,
    required EnrichmentOwnershipRepository ownershipRepository,
    AllDeckIdsPort? allDeckIdsPort,
  }) : _maintenanceRepository = maintenanceRepository,
       _jobRepository = jobRepository,
       _ownershipRepository = ownershipRepository,
       _allDeckIdsPort = allDeckIdsPort;

  /// Crash recovery for the queue tables: any row left `running` by a
  /// process that died mid-claim (app kill, crash) would otherwise be
  /// invisible to both `claimBaseWorkBatch` and `claimNextINatWorkItem`
  /// (they only select `pending`/`retryScheduled`), permanently stranding
  /// that species. Cheap no-op when nothing was interrupted.
  Future<void> recoverInterruptedWork() => _repair(
    'Recovering interrupted enrichment work',
    _maintenanceRepository.recoverInterruptedWork,
  );

  /// One-time sweep for job/species-work rows left behind by decks deleted
  /// before `deleteDeckJob`/`releaseDeck` replaced the old soft-cancel
  /// behavior. Cheap no-op on every run after the first, since new deletions
  /// no longer leave orphans.
  Future<void> pruneOrphanedWork() async {
    final port = _allDeckIdsPort;
    if (port == null) return;
    await _repair('Pruning orphaned enrichment work', () async {
      final validDeckIds = await port.loadAllDeckIds();
      await _jobRepository.pruneJobsNotIn(validDeckIds);
      final trackedDeckIds = await _ownershipRepository
          .loadAllDeckSpeciesSnapshots();
      for (final deckId in trackedDeckIds.keys) {
        if (validDeckIds.contains(deckId)) continue;
        await _ownershipRepository.releaseDeck(deckId);
      }
    });
  }

  Future<void> _repair(String what, Future<void> Function() repair) async {
    try {
      await runToleratingClosedDatabase(_log, repair);
    } catch (error, stackTrace) {
      _log.warn('$what failed', error: error, stackTrace: stackTrace);
    }
  }
}
