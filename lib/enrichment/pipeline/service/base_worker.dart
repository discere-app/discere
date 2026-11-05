import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/enrichment/model/enrichment_capability.dart';
import 'package:discere/enrichment/model/enrichment_work_state.dart';
import 'package:discere/enrichment/pipeline/model/base_image_download_result.dart';
import 'package:discere/enrichment/pipeline/model/base_image_fallback_reason.dart';
import 'package:discere/enrichment/pipeline/model/base_image_retry_policy.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_claim_repository.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_outcome_repository.dart';
import 'package:discere/enrichment/pipeline/service/base_image_enrichment_service.dart';
import 'package:discere/enrichment/service/enrichment_failure_classifier.dart';
import 'package:discere/shared/persistence/closed_database_tolerance.dart';
import 'package:discere/shared/persistence/reference_database_provisioner.dart';
import 'package:discere/shared/util/concurrency_utils.dart';
import 'package:discere/shared/util/logger.dart';

/// Drains species needing `base` (reference-image) work: downloads
/// FishBase/SealifeBase reference images with real concurrency, entirely
/// independent of the rate-limited iNaturalist path.
///
/// This is one half of the producer-consumer enrichment pipeline (see the
/// enrichment-optimization plan / GitHub issues #56, #57) — [BaseWorker] and
/// `INatWorker` are two independently-scheduled loops sharing the queue
/// tables behind [EnrichmentWorkClaimRepository]. Because base-image
/// downloads hit a
/// different host than iNaturalist's rate-limited API (no artificial request
/// spacing, real concurrency), this worker never needs to wait on — or be
/// waited on by — the iNat worker; it just reports what it learns about each
/// species (via [EnrichmentWorkOutcomeRepository.seedCapability]) the moment it
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

  static const _inatPrimaryPriorityTier = 10;
  static const _inatBackfillPriorityTier = 40;

  /// Defensive circuit breaker against an unbounded loop — not expected to
  /// ever be hit in practice, since each batch only reclaims species that
  /// are still genuinely eligible (pending, or a past-due retry).
  static const _maxBatchRuns = 200;

  final BaseImageEnrichmentService _baseImageEnrichmentService;
  final EnrichmentWorkClaimRepository _claimRepository;
  final EnrichmentWorkOutcomeRepository _outcomeRepository;
  final SpeciesRepository _speciesRepository;

  const BaseWorker(
    this._baseImageEnrichmentService,
    this._claimRepository,
    this._outcomeRepository,
    this._speciesRepository,
  );

  /// Repeatedly claims and processes batches of species needing `base` work
  /// until either the queue is drained or [shouldStop] returns true. Returns
  /// whether any work was actually processed. A user database closed
  /// underneath the loop ends it early. Any other database error propagates
  /// from claiming; one raised while processing a species is booked as that
  /// species' failed attempt (see [_runOne]).
  ///
  /// [onProgress], if given, fires after every single species is processed
  /// (not just once per batch/pass) — the UI-facing progress refresh this
  /// drives is cheap and self-coalescing (see
  /// `INatEnrichmentQueueService._refreshState`), so per-species granularity
  /// here is what lets the deck-card progress move during a long batch
  /// instead of jumping only once the whole `runUntilIdle` call returns.
  Future<bool> runUntilIdle({
    required bool Function() shouldStop,
    void Function()? onProgress,
  }) async {
    var processedAny = false;
    await runToleratingClosedDatabase(_log, () async {
      final referenceDbVersion = await ReferenceDatabaseProvisioner
          .currentVersion();
      for (var batchRun = 0; batchRun < _maxBatchRuns; batchRun++) {
        if (shouldStop()) break;
        final speciesIds = await _claimRepository.claimBaseWorkBatch(
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
          task: (species) async {
            await _runOne(species, referenceDbVersion);
            onProgress?.call();
          },
        );
      }
    });
    return processedAny;
  }

  Future<void> _runOne(Species species, int? referenceDbVersion) async {
    try {
      if (!_hasReferencePicture(species)) {
        // Structural fact, not a failure: there is nothing to download, so
        // retrying against the reference-image host would never help. Fall
        // back to iNaturalist immediately instead of burning attempts.
        _log.debug(
          'No reference-image URL for ${species.id} — marking base '
          'noResult, falling back to iNat',
        );
        await _outcomeRepository.markCapabilityTerminal(
          species.id,
          EnrichmentCapability.base,
          EnrichmentWorkState.noResult,
          referenceDbVersion: referenceDbVersion,
        );
        await _seedINatFallback(species.id);
        return;
      }

      final result = await _baseImageEnrichmentService.downloadReferenceImages(
        species,
      );
      switch (result) {
        case BaseImageSaved():
          await _outcomeRepository.markCapabilityTerminal(
            species.id,
            EnrichmentCapability.base,
            EnrichmentWorkState.done,
            referenceDbVersion: referenceDbVersion,
          );
          // The species now has an image, but still only from the reference
          // DB — seed a low-priority backfill item so it can eventually pick
          // up an iNaturalist photo too, without competing with species that
          // have no image at all yet (see INatWorker's priority tiers).
          await _outcomeRepository.seedCapability(
            species.id,
            EnrichmentCapability.inatBackfill,
            priorityTier: _inatBackfillPriorityTier,
          );
        case BaseImageFailed(:final reason, :final host):
          final failure = host == null
              ? reason.wireName
              : '${reason.wireName} at $host';
          _log.warn('Base image download failed for ${species.id}: $failure');
          await _recordFailure(
            species.id,
            reason: reason,
            host: host,
            error: failure,
            referenceDbVersion: referenceDbVersion,
          );
      }
    } catch (error, stackTrace) {
      // A real database error is booked like any other failure, so a
      // species that keeps failing burns its own retries instead of being
      // claimed first again on every pass. A closed database is no
      // species' failure, and nothing could book it: it ends the loop in
      // runUntilIdle instead.
      if (isClosedDatabaseError(error)) rethrow;
      _log.warn(
        'Base image download failed for ${species.id}',
        error: error,
        stackTrace: stackTrace,
      );
      await _recordFailure(
        species.id,
        reason: BaseImageFallbackReason.other,
        host: null,
        error: error.toString(),
        referenceDbVersion: referenceDbVersion,
      );
    }
  }

  /// Books the failed attempt under [BaseImageRetryPolicy] and, once the
  /// species stops waiting for its reference image, falls back to
  /// iNaturalist. Unless the host said the image is missing, the reference
  /// image is still retried after that, so a host outage costs the species
  /// its reference image only for as long as it lasts.
  Future<void> _recordFailure(
    String speciesId, {
    required BaseImageFallbackReason reason,
    required String? host,
    required String error,
    required int? referenceDbVersion,
  }) async {
    final fallsBack = await _outcomeRepository.recordBaseImageAttemptFailure(
      speciesId,
      reason: reason,
      host: host,
      error: error,
      failureKind: BaseImageRetryPolicy.givesUpAtOnce(reason)
          ? EnrichmentFailureKind.permanent.name
          : EnrichmentFailureKind.temporary.name,
      referenceDbVersion: referenceDbVersion,
    );
    if (fallsBack) {
      _log.warn(
        'Falling back to iNaturalist for $speciesId (${reason.wireName})',
      );
      await _seedINatFallback(speciesId);
    }
  }

  Future<void> _seedINatFallback(String speciesId) async {
    await _outcomeRepository.seedCapability(
      speciesId,
      EnrichmentCapability.inatPrimary,
      priorityTier: _inatPrimaryPriorityTier,
    );
    await _outcomeRepository.seedCapability(
      speciesId,
      EnrichmentCapability.inatBackfill,
      priorityTier: _inatBackfillPriorityTier,
    );
  }

  bool _hasReferencePicture(Species species) {
    return species.pictures.any((picture) => (picture.url ?? '').isNotEmpty);
  }
}
