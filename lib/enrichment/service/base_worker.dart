import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/enrichment/model/enrichment_job.dart';
import 'package:discere/enrichment/repository/enrichment_work_repository.dart';
import 'package:discere/enrichment/service/enrichment_service.dart';
import 'package:discere/shared/util/concurrency_utils.dart';
import 'package:discere/shared/util/logger.dart';

/// Drains species needing `base` (reference-image) work: downloads
/// FishBase/SealifeBase reference images with real concurrency, entirely
/// independent of the rate-limited iNaturalist path.
///
/// This is one half of the producer-consumer enrichment pipeline (see the
/// enrichment-optimization plan / GitHub issues #56, #57) — [BaseWorker] and
/// `INatWorker` are two independently-scheduled loops sharing the queue
/// tables in [EnrichmentWorkRepository]. Because base-image downloads hit a
/// different host than iNaturalist's rate-limited API (no artificial request
/// spacing, real concurrency), this worker never needs to wait on — or be
/// waited on by — the iNat worker; it just reports what it learns about each
/// species (via [EnrichmentWorkRepository.seedCapability]) the moment it
/// knows, instead of gating the whole batch behind a single decision point.
class BaseWorker {
  static final _log = Logger.forType(BaseWorker);

  /// Base-image downloads aren't rate-limited, but a bounded concurrency
  /// still keeps local resource usage (file writes, HTTP connections) in
  /// check.
  static const _maxConcurrent = 3;

  /// Batch size for claiming pending species — keeps checkpoint writes and
  /// per-batch memory usage proportional rather than loading the whole
  /// queue at once.
  static const _batchSize = 25;

  /// After this many failed download attempts against the reference-image
  /// host, give up and fall back to iNaturalist instead of retrying forever.
  static const _maxAttempts = 5;

  /// Escalating backoff applied between retry attempts.
  static const _retryBackoffSteps = [
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 2),
    Duration(minutes: 4),
  ];

  static const _inatPrimaryPriorityTier = 10;
  static const _inatBackfillPriorityTier = 40;

  /// Defensive circuit breaker against an unbounded loop — not expected to
  /// ever be hit in practice, since each batch only reclaims species that
  /// are still genuinely eligible (pending, or a past-due retry).
  static const _maxBatchRuns = 200;

  final EnrichmentService _enrichmentService;
  final EnrichmentWorkRepository _workRepository;
  final SpeciesRepository _speciesRepository;

  const BaseWorker(
    this._enrichmentService,
    this._workRepository,
    this._speciesRepository,
  );

  /// Repeatedly claims and processes batches of species needing `base` work
  /// until either the queue is drained or [shouldStop] returns true. Returns
  /// whether any work was actually processed.
  Future<bool> runUntilIdle({required bool Function() shouldStop}) async {
    var processedAny = false;
    for (var batchRun = 0; batchRun < _maxBatchRuns; batchRun++) {
      if (shouldStop()) break;
      final speciesIds = await _workRepository.claimBaseWorkBatch(
        limit: _batchSize,
      );
      if (speciesIds.isEmpty) break;
      processedAny = true;
      _log.debug('Claimed base-work batch size=${speciesIds.length}');

      final speciesList = (await _speciesRepository.getSpecies(
        speciesIds.toSet(),
      )).toList(growable: false);
      await runConcurrently<Species>(
        speciesList,
        maxConcurrent: _maxConcurrent,
        isCancelled: shouldStop,
        task: _runOne,
      );
    }
    return processedAny;
  }

  Future<void> _runOne(Species species) async {
    try {
      if (!_hasReferencePicture(species)) {
        // Structural fact, not a failure: there is nothing to download, so
        // retrying against the reference-image host would never help. Fall
        // back to iNaturalist immediately instead of burning attempts.
        await _workRepository.markCapabilityTerminal(
          species.id,
          EnrichmentStage.base,
          'noResult',
        );
        await _seedINatFallback(species.id);
        return;
      }

      final summary = await _enrichmentService.downloadBaseImagesForSpecies({
        species.id,
      });
      if (summary.imageCount > 0) {
        await _workRepository.markCapabilityTerminal(
          species.id,
          EnrichmentStage.base,
          'done',
        );
        // The species now has an image, but still only from the reference
        // DB — seed a low-priority backfill item so it can eventually pick
        // up an iNaturalist photo too, without competing with species that
        // have no image at all yet (see INatWorker's priority tiers).
        await _workRepository.seedCapability(
          species.id,
          EnrichmentStage.inatBackfill,
          priorityTier: _inatBackfillPriorityTier,
        );
        return;
      }

      await _retryOrFallBack(
        species.id,
        error: 'Base image download returned no images',
      );
    } catch (error) {
      _log.warn('Base image download failed for ${species.id}: $error');
      await _retryOrFallBack(species.id, error: error.toString());
    }
  }

  /// Retries the download against the reference-image host up to
  /// [_maxAttempts] times (with escalating backoff) before falling back to
  /// iNaturalist — a single transient blip against that host shouldn't burn
  /// iNaturalist's much more constrained request budget.
  Future<void> _retryOrFallBack(
    String speciesId, {
    required String error,
  }) async {
    final gaveUp = await _workRepository.recordCapabilityAttemptFailure(
      speciesId,
      EnrichmentStage.base,
      maxAttempts: _maxAttempts,
      backoffSteps: _retryBackoffSteps,
      error: error,
      failureKind: 'temporary',
    );
    if (gaveUp) {
      _log.warn(
        'Giving up on base image for $speciesId after $_maxAttempts '
        'attempts — falling back to iNaturalist',
      );
      await _seedINatFallback(speciesId);
    }
  }

  Future<void> _seedINatFallback(String speciesId) async {
    await _workRepository.seedCapability(
      speciesId,
      EnrichmentStage.inatPrimary,
      priorityTier: _inatPrimaryPriorityTier,
    );
    await _workRepository.seedCapability(
      speciesId,
      EnrichmentStage.inatBackfill,
      priorityTier: _inatBackfillPriorityTier,
    );
  }

  bool _hasReferencePicture(Species species) {
    return species.pictures.any((picture) => (picture.url ?? '').isNotEmpty);
  }
}
