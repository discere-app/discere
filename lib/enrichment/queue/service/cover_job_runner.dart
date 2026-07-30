import 'package:discere/diagnostics/service/local_diagnostics.dart';
import 'package:discere/enrichment/ports/enrichment_job_ports.dart';
import 'package:discere/enrichment/queue/repository/enrichment_job_repository.dart';
import 'package:discere/enrichment/queue/service/enrichment_failure_classifier.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:discere/shared/util/logger.dart';

/// Runs the deck-cover job — the only job left after the producer-consumer
/// rewrite (see the enrichment-optimization plan / GitHub issues #56, #57).
/// Species/taxonomy enrichment no longer goes through a claimed job stage at
/// all; see `BaseWorker`/`INatWorker` instead. This class replaces the old
/// `EnrichmentJobExecutor`, which handled six stages — now there is only one.
class CoverJobRunner {
  static final _log = Logger.forType(CoverJobRunner);

  /// A job that keeps failing with a "temporary" classification (timeouts,
  /// transport errors) retries indefinitely otherwise — this caps it so the
  /// job surfaces as `failedPermanent` instead of silently looping forever.
  static const _maxTemporaryRetries = 5;

  static const _maxJobRuns = 24;

  final EnrichmentJobRepository _jobRepository;
  final DeckCoverStorePort _deckCoverStore;
  final ImageService _imageService;
  final LocalDiagnostics _diagnostics;

  const CoverJobRunner(
    this._jobRepository,
    this._deckCoverStore,
    this._imageService, {
    required LocalDiagnostics diagnostics,
  }) : _diagnostics = diagnostics;

  Future<bool> runUntilIdle({
    required String owner,
    required EnrichmentRunnerKind runnerKind,
    Duration leaseDuration = const Duration(minutes: 15),
    int maxJobRuns = _maxJobRuns,
    bool Function()? shouldStop,
  }) async {
    var processedAny = false;
    for (var i = 0; i < maxJobRuns; i++) {
      if (shouldStop?.call() ?? false) break;

      final job = await _jobRepository.claimNextJob(
        owner: owner,
        leaseDuration: leaseDuration,
        runnerKind: runnerKind,
      );
      if (job == null) break;
      final stage = _jobRepository.nextRunnableStage(job);
      if (stage == null) break;

      processedAny = true;
      _log.debug(
        'Execute cover job deck=${job.deckId} runner=${runnerKind.name}',
      );
      final stopwatch = Stopwatch()..start();
      await _diagnostics.recordEvent(
        category: 'enrichment',
        eventType: 'stage_started',
        subjectType: 'deck',
        subjectId: job.deckId,
        details: {'runnerKind': runnerKind.name, 'stage': stage.name},
      );
      await _jobRepository.markStageRunning(
        deckId: job.deckId,
        stage: stage,
        owner: owner,
        runnerKind: runnerKind,
      );

      try {
        final coverImageUrl = job.payload.coverImageUrl?.trim();
        if (coverImageUrl != null && coverImageUrl.isNotEmpty) {
          final isActiveBeforeDownload = await _jobRepository.isJobActive(
            deckId: job.deckId,
            owner: owner,
          );
          if (isActiveBeforeDownload) {
            _log.debug('Download cover deck=${job.deckId} url=$coverImageUrl');
            final localPath = await _imageService.downloadAndSaveDeckCover(
              coverImageUrl,
            );
            final isActiveAfterDownload = await _jobRepository.isJobActive(
              deckId: job.deckId,
              owner: owner,
            );
            if (isActiveAfterDownload) {
              await _deckCoverStore.updateDeckCoverPath(job.deckId, localPath);
            }
          }
        }
        // Always attempted, even if the checks above skipped the download —
        // markStageSucceeded is a safe no-op if the job was deleted or its
        // lease moved on in the meantime (see _loadJobLeasedBy).
        await _jobRepository.markStageSucceeded(
          deckId: job.deckId,
          stage: stage,
          owner: owner,
        );
        stopwatch.stop();
        await _diagnostics.recordEvent(
          category: 'enrichment',
          eventType: 'stage_succeeded',
          subjectType: 'deck',
          subjectId: job.deckId,
          durationMs: stopwatch.elapsedMilliseconds,
          details: {'runnerKind': runnerKind.name, 'stage': stage.name},
        );
      } catch (error) {
        stopwatch.stop();
        final failureKind = classifyEnrichmentFailure(error);
        final retriesExhausted =
            failureKind == EnrichmentFailureKind.temporary &&
            job.retryCount + 1 >= _maxTemporaryRetries;
        final isPermanentOutcome =
            failureKind == EnrichmentFailureKind.permanent || retriesExhausted;
        if (isPermanentOutcome) {
          await _jobRepository.markStageFailedPermanent(
            deckId: job.deckId,
            stage: stage,
            owner: owner,
            error: error.toString(),
            failureKind: retriesExhausted
                ? '${failureKind.name}_retries_exhausted'
                : failureKind.name,
          );
        } else {
          await _jobRepository.markStageRetryScheduled(
            deckId: job.deckId,
            stage: stage,
            owner: owner,
            error: error.toString(),
            failureKind: failureKind.name,
          );
        }
        await _diagnostics.recordEvent(
          category: 'enrichment',
          eventType: isPermanentOutcome
              ? 'stage_failed_permanent'
              : 'stage_retry_scheduled',
          subjectType: 'deck',
          subjectId: job.deckId,
          durationMs: stopwatch.elapsedMilliseconds,
          level: 'warning',
          message: error.toString(),
          details: {
            'runnerKind': runnerKind.name,
            'stage': stage.name,
            'failureKind': failureKind.name,
            if (retriesExhausted) 'retriesExhausted': true,
          },
        );
        _log.warn(
          'Cover job failed for ${job.deckId} (${failureKind.name}): $error',
        );
      }
    }
    return processedAny;
  }
}
