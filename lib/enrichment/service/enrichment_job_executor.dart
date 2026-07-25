import 'dart:async';

import 'package:discere/diagnostics/service/local_diagnostics.dart';
import 'package:discere/enrichment/repository/enrichment_job_repository.dart';
import 'package:discere/enrichment/repository/enrichment_work_repository.dart';
import 'package:discere/enrichment/service/enrichment_failure_classifier.dart';
import 'package:discere/enrichment/service/enrichment_job_ports.dart';
import 'package:discere/enrichment/service/enrichment_progress_status.dart';
import 'package:discere/enrichment/service/enrichment_run_completion_summary.dart';
import 'package:discere/enrichment/service/enrichment_service.dart';
import 'package:discere/enrichment/service/taxonomy_common_name_enrichment_service.dart';
import 'package:discere/enrichment/util/ordered_unique_strings.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:discere/shared/util/logger.dart';

class EnrichmentJobExecutor {
  static final _log = Logger.forType(EnrichmentJobExecutor);
  static const backgroundINatMaxConcurrent = 1;
  static const backgroundINatRequestSpacing = Duration(milliseconds: 1100);
  static const _baseStageBatchSize = 25;
  static const _primaryINatBatchSize = 12;
  static const _namesBatchSize = 12;
  static const _backfillINatBatchSize = 8;
  // A stage that keeps failing with a "temporary" classification (timeouts,
  // transport errors) retries indefinitely otherwise — this caps it so the
  // job surfaces as failedPermanent instead of silently looping forever.
  static const _maxTemporaryRetries = 5;
  // Number of terminal species outcomes to accumulate before writing a
  // checkpoint. Keeps DB writes and UI refreshes proportional to batch size
  // rather than firing once per species.
  static const _checkpointFlushSize = 5;
  // Per-species cap for checkpointed species-stage runners (base, inatPrimary,
  // names, inatBackfill). Those runners deliberately swallow per-species
  // errors (see EnrichmentService's doc comments) so one broken species
  // doesn't block the rest of a batch — which means a persistently failing
  // species never throws and so never reaches _maxTemporaryRetries above.
  // Without this cap such a species would stay "remaining" forever, which for
  // base/inatPrimary specifically blocks
  // EnrichmentJobRecord.everySpeciesHasImage — and therefore the flashcard
  // review session — indefinitely. After this many attempts within a stage,
  // _runSpeciesStageWithCheckpoint forces the species terminal so the stage
  // can still converge.
  static const _maxSpeciesStageAttempts = 5;

  final EnrichmentService _enrichmentService;
  final TaxonomyCommonNameEnrichmentService _taxonomyEnrichmentService;
  final EnrichmentJobRepository _jobRepository;
  final EnrichmentWorkRepository _workRepository;
  final DeckCoverStorePort _deckCoverStore;
  final ImageService _imageService;
  final ScientificNameResolutionPort? _nameResolutionPort;
  final DeckSpeciesMutationPort? _deckSpeciesMutationPort;
  final UnresolvedNamesObserverPort? _unresolvedNamesObserver;
  final Future<void> Function()? _onStateChanged;
  final LocalDiagnostics _diagnostics;

  EnrichmentJobExecutor(
    this._enrichmentService,
    this._jobRepository, {
    required TaxonomyCommonNameEnrichmentService taxonomyEnrichmentService,
    required DeckCoverStorePort deckCoverStore,
    required ImageService imageService,
    required EnrichmentWorkRepository workRepository,
    required LocalDiagnostics diagnostics,
    ScientificNameResolutionPort? nameResolutionPort,
    DeckSpeciesMutationPort? deckSpeciesMutationPort,
    UnresolvedNamesObserverPort? unresolvedNamesObserver,
    Future<void> Function()? onStateChanged,
  }) : _taxonomyEnrichmentService = taxonomyEnrichmentService,
       _deckCoverStore = deckCoverStore,
       _workRepository = workRepository,
       _imageService = imageService,
       _nameResolutionPort = nameResolutionPort,
       _deckSpeciesMutationPort = deckSpeciesMutationPort,
       _unresolvedNamesObserver = unresolvedNamesObserver,
       _onStateChanged = onStateChanged,
       _diagnostics = diagnostics;

  Future<void> _reportProgress({
    required String deckId,
    required int completed,
    required int total,
  }) async {
    await _jobRepository.updateProgress(
      deckId: deckId,
      completed: completed,
      total: total,
    );
    if (_onStateChanged != null) {
      await _onStateChanged();
    }
  }

  Future<bool> processUntilIdle({
    required String owner,
    required EnrichmentRunnerKind runnerKind,
    Duration leaseDuration = const Duration(minutes: 15),
    int maxStageRuns = 24,
    bool Function()? shouldStop,
  }) async {
    var processedAny = false;
    var processedStages = 0;
    final runId =
        '${runnerKind.name}-$owner-${DateTime.now().microsecondsSinceEpoch}';
    final runStopwatch = Stopwatch()..start();
    final completionCollector =
        _diagnostics.isEnrichmentCompletionSummaryEnabled
        ? RunCompletionSummaryCollector()
        : null;
    await _diagnostics.recordEvent(
      category: 'enrichment',
      eventType: 'run_started',
      runId: runId,
      owner: owner,
      details: {
        'runnerKind': runnerKind.name,
        'maxStageRuns': maxStageRuns,
        'leaseDurationMs': leaseDuration.inMilliseconds,
      },
    );
    for (var i = 0; i < maxStageRuns; i++) {
      if (shouldStop?.call() ?? false) {
        break;
      }
      final job = await _jobRepository.claimNextJob(
        owner: owner,
        leaseDuration: leaseDuration,
        runnerKind: runnerKind,
      );
      if (job == null) break;

      final stage = _jobRepository.nextRunnableStage(job);
      if (stage == null) break;

      processedAny = true;
      processedStages++;
      _log.debug(
        'Execute stage deck=${job.deckId} stage=${stage.name} '
        'runner=${runnerKind.name} species=${job.payload.speciesIds.length} '
        'unresolved=${job.payload.unresolvedSpeciesNames.length}',
      );
      final stageProgress = deriveDisplayedProgress(job, stage: stage);
      final stageStopwatch = Stopwatch()..start();
      await _diagnostics.recordEvent(
        category: 'enrichment',
        eventType: 'stage_started',
        runId: runId,
        owner: owner,
        subjectType: 'deck',
        subjectId: job.deckId,
        details: {
          'runnerKind': runnerKind.name,
          'stage': stage.name,
          'speciesCount': job.payload.speciesIds.length,
          'unresolvedNamesCount': job.payload.unresolvedSpeciesNames.length,
        },
      );
      await _jobRepository.markStageRunning(
        deckId: job.deckId,
        stage: stage,
        owner: owner,
        runnerKind: runnerKind,
        progressCompleted: stageProgress.completed,
        progressTotal: stageProgress.total,
      );
      if (_onStateChanged != null) {
        await _onStateChanged();
      }

      try {
        final outcome = await _diagnostics.runScope(
          category: 'enrichment',
          timelineName: 'enrichment:${stage.name}',
          runId: runId,
          subjectType: 'deck',
          subjectId: job.deckId,
          details: {'runnerKind': runnerKind.name, 'stage': stage.name},
          action: () => _runStage(
            job.deckId,
            job.payload,
            stage,
            captureCompletionSummary: completionCollector != null,
            owner: owner,
            shouldCancel: () async => !(await _jobRepository.isJobActive(
              deckId: job.deckId,
              owner: owner,
            )),
          ),
        );
        if (outcome.completedStage) {
          await _jobRepository.markStageSucceeded(
            deckId: job.deckId,
            stage: stage,
            owner: owner,
            payload: outcome.payload,
          );
          _log.debug(
            'Stage success deck=${job.deckId} stage=${stage.name} '
            'runner=${runnerKind.name}',
          );
        } else {
          await _jobRepository.markStageYielded(
            deckId: job.deckId,
            stage: stage,
            owner: owner,
            payload: outcome.payload,
            completed: outcome.completed,
            total: outcome.total,
          );
          _log.debug(
            'Stage yielded deck=${job.deckId} stage=${stage.name} '
            'runner=${runnerKind.name} completed=${outcome.completed}/${outcome.total}',
          );
        }
        if (completionCollector != null && outcome.completionSummary != null) {
          completionCollector.recordStageOutcome(outcome.completionSummary!);
          _log.debug(
            'Stage summary deck=${job.deckId} stage=${stage.name} '
            'terminal=${outcome.completionSummary!.completedSpeciesIds.length}/'
            '${outcome.completionSummary!.plannedSpeciesIds.length} '
            'remainingErrors='
            '${outcome.completionSummary!.speciesIdsWithRemainingErrors.length}',
          );
        }
        stageStopwatch.stop();
        await _diagnostics.recordEvent(
          category: 'enrichment',
          eventType: outcome.completedStage
              ? 'stage_succeeded'
              : 'stage_yielded',
          runId: runId,
          owner: owner,
          subjectType: 'deck',
          subjectId: job.deckId,
          durationMs: stageStopwatch.elapsedMilliseconds,
          details: {
            'runnerKind': runnerKind.name,
            'stage': stage.name,
            'progressCompleted': outcome.completed,
            'progressTotal': outcome.total,
            if (outcome.completionSummary != null) ...{
              'plannedSpeciesCount':
                  outcome.completionSummary!.plannedSpeciesIds.length,
              'terminalSpeciesCount':
                  outcome.completionSummary!.completedSpeciesIds.length,
              'remainingFailureSpeciesCount': outcome
                  .completionSummary!
                  .speciesIdsWithRemainingErrors
                  .length,
            },
          },
        );
        if (_onStateChanged != null) {
          await _onStateChanged();
        }
      } catch (error) {
        stageStopwatch.stop();
        final failureKind = classifyEnrichmentFailure(error);
        final retriesExhausted =
            failureKind == EnrichmentFailureKind.temporary &&
            job.retryCount + 1 >= _maxTemporaryRetries;
        final isPermanentOutcome =
            failureKind == EnrichmentFailureKind.permanent || retriesExhausted;
        if (completionCollector != null && isPermanentOutcome) {
          completionCollector.recordPermanentStageFailure(
            stage: stage,
            affectedSpeciesIds: _speciesIdsForStage(job.payload, stage),
          );
        }
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
          runId: runId,
          owner: owner,
          subjectType: 'deck',
          subjectId: job.deckId,
          durationMs: stageStopwatch.elapsedMilliseconds,
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
          'Enrichment failed for ${job.deckId} '
          '(${stage.name}, ${failureKind.name}): $error',
        );
        if (_onStateChanged != null) {
          await _onStateChanged();
        }
      }
    }
    runStopwatch.stop();
    final pendingWork = await _jobRepository.hasPendingWork();
    final completionSummary = completionCollector?.finalize(
      queueDrained: !pendingWork,
    );
    if (completionSummary != null) {
      _log.debug(
        'Run summary runId=$runId status=${completionSummary.status} '
        'queueDrained=${completionSummary.queueDrained} '
        'fullyEnriched=${completionSummary.fullyEnriched} '
        'allErrorsResolved=${completionSummary.allErrorsResolved} '
        'species=${completionSummary.fullyEnrichedSpeciesCount}/'
        '${completionSummary.plannedSpeciesCount} '
        'remainingFailures=${completionSummary.remainingFailureSpeciesCount} '
        'permanentFailures=${completionSummary.permanentFailureCount}',
      );
    }
    await _diagnostics.recordEvent(
      category: 'enrichment',
      eventType: 'run_finished',
      runId: runId,
      owner: owner,
      durationMs: runStopwatch.elapsedMilliseconds,
      details: {
        'runnerKind': runnerKind.name,
        'processedAny': processedAny,
        'processedStages': processedStages,
        'pendingWork': pendingWork,
        if (completionSummary != null) ...completionSummary.toDetails(),
      },
    );
    return processedAny;
  }

  Future<_StageRunOutcome> _runStage(
    String deckId,
    EnrichmentJobPayload payload,
    EnrichmentStage stage, {
    required bool captureCompletionSummary,
    required String owner,
    required Future<bool> Function() shouldCancel,
  }) async {
    switch (stage) {
      case EnrichmentStage.nameResolution:
        return _runNameResolutionStage(
          deckId,
          payload,
          captureCompletionSummary: captureCompletionSummary,
          shouldCancel: shouldCancel,
        );
      case EnrichmentStage.cover:
        await _runCoverStage(deckId, payload, shouldCancel: shouldCancel);
        return _StageRunOutcome.completed(
          payload: payload,
          completed: 0,
          total: 0,
        );
      case EnrichmentStage.base:
        return _runBaseStage(
          deckId,
          payload,
          captureCompletionSummary: captureCompletionSummary,
          owner: owner,
          shouldCancel: shouldCancel,
        );
      case EnrichmentStage.inatPrimary:
        return _runPrimaryINatStage(
          deckId,
          payload,
          captureCompletionSummary: captureCompletionSummary,
          owner: owner,
          shouldCancel: shouldCancel,
        );
      case EnrichmentStage.names:
        return _runCommonNameStage(
          deckId,
          payload,
          captureCompletionSummary: captureCompletionSummary,
          owner: owner,
          shouldCancel: shouldCancel,
        );
      case EnrichmentStage.inatBackfill:
        return _runBackfillINatStage(
          deckId,
          payload,
          captureCompletionSummary: captureCompletionSummary,
          owner: owner,
          shouldCancel: shouldCancel,
        );
    }
  }

  Future<_StageRunOutcome> _runNameResolutionStage(
    String deckId,
    EnrichmentJobPayload payload, {
    required bool captureCompletionSummary,
    required Future<bool> Function() shouldCancel,
  }) async {
    final namesToResolve = payload.unresolvedSpeciesNames;
    if (namesToResolve.isEmpty ||
        _nameResolutionPort == null ||
        _deckSpeciesMutationPort == null) {
      _log.debug(
        'Skip name resolution deck=$deckId names=${namesToResolve.length} '
        'resolver=${_nameResolutionPort != null} mutation=${_deckSpeciesMutationPort != null}',
      );
      final nextPayload = payload.copyWith(
        stillUnresolvedNames: namesToResolve,
      );
      return _StageRunOutcome.completed(
        payload: nextPayload,
        completed: namesToResolve.length,
        total: namesToResolve.length,
      );
    }
    if (await shouldCancel()) {
      return _StageRunOutcome.completed(
        payload: payload,
        completed: 0,
        total: namesToResolve.length,
      );
    }

    await _reportProgress(
      deckId: deckId,
      completed: 0,
      total: namesToResolve.length,
    );

    final resolved = await _nameResolutionPort.resolveNames(namesToResolve);
    if (await shouldCancel()) {
      return _StageRunOutcome.completed(
        payload: payload,
        completed: 0,
        total: namesToResolve.length,
      );
    }
    if (resolved.isNotEmpty) {
      await _deckSpeciesMutationPort.addSpeciesToDeck(
        deckId,
        resolved.values.toSet(),
      );
    }
    final mergedSpeciesIds = {
      ...payload.speciesIds,
      ...resolved.values,
    }.toList();

    final stillUnresolved = namesToResolve
        .where((name) => !resolved.containsKey(name))
        .toList();
    await _reportProgress(
      deckId: deckId,
      completed: namesToResolve.length,
      total: namesToResolve.length,
    );

    if (stillUnresolved.isNotEmpty) {
      _log.warn(
        'Name resolution for deck $deckId: '
        '${stillUnresolved.length}/${namesToResolve.length} species still unresolved: '
        '${stillUnresolved.join(", ")}',
      );
      _unresolvedNamesObserver?.onNamesUnresolved(deckId, stillUnresolved);
    } else {
      _log.debug(
        'Name resolution for deck $deckId: '
        'all ${namesToResolve.length} species resolved via iNaturalist',
      );
    }

    final nextPayload = payload.copyWith(
      speciesIds: mergedSpeciesIds,
      stillUnresolvedNames: stillUnresolved,
    );
    return _StageRunOutcome.completed(
      payload: nextPayload,
      completed: namesToResolve.length,
      total: namesToResolve.length,
    );
  }

  Future<void> _runCoverStage(
    String deckId,
    EnrichmentJobPayload payload, {
    required Future<bool> Function() shouldCancel,
  }) async {
    final coverImageUrl = payload.coverImageUrl?.trim();
    if (coverImageUrl == null || coverImageUrl.isEmpty) {
      _log.debug('Skip cover stage deck=$deckId no cover URL');
      return;
    }
    if (await shouldCancel()) return;
    _log.debug('Download cover deck=$deckId url=$coverImageUrl');
    final localPath = await _imageService.downloadAndSaveDeckCover(
      coverImageUrl,
    );
    if (await shouldCancel()) return;
    await _deckCoverStore.updateDeckCoverPath(deckId, localPath);
  }

  Future<_StageRunOutcome> _runBaseStage(
    String deckId,
    EnrichmentJobPayload payload, {
    required bool captureCompletionSummary,
    required String owner,
    required Future<bool> Function() shouldCancel,
  }) async {
    return _runSpeciesStageWithCheckpoint(
      deckId,
      payload,
      stage: EnrichmentStage.base,
      captureCompletionSummary: captureCompletionSummary,
      owner: owner,
      shouldCancel: shouldCancel,
      batchSize: _baseStageBatchSize,
      runner: (remainingSpeciesIds, onSpeciesCompleted) async {
        _log.debug(
          'Run base stage deck=$deckId species=${remainingSpeciesIds.length}',
        );
        final summary = await _enrichmentService.downloadBaseImagesForSpecies(
          remainingSpeciesIds,
          onSpeciesCompleted: onSpeciesCompleted,
        );
        return _SpeciesStageRunnerDiagnostics(
          anyImageDownloaded: summary.imageCount > 0,
        );
      },
    );
  }

  Future<_StageRunOutcome> _runPrimaryINatStage(
    String deckId,
    EnrichmentJobPayload payload, {
    required bool captureCompletionSummary,
    required String owner,
    required Future<bool> Function() shouldCancel,
  }) async {
    return _runSpeciesStageWithCheckpoint(
      deckId,
      payload,
      stage: EnrichmentStage.inatPrimary,
      captureCompletionSummary: captureCompletionSummary,
      owner: owner,
      shouldCancel: shouldCancel,
      batchSize: _primaryINatBatchSize,
      runner: (remainingSpeciesIds, onSpeciesCompleted) async {
        _log.debug(
          'Run iNat primary stage deck=$deckId species=${remainingSpeciesIds.length}',
        );
        final summary = await _enrichmentService.fetchINatPhotosForSpecies(
          remainingSpeciesIds,
          primaryOnly: true,
          prioritizeSpeciesWithoutImages: true,
          maxConcurrent: backgroundINatMaxConcurrent,
          requestSpacing: backgroundINatRequestSpacing,
          onSpeciesCompleted: onSpeciesCompleted,
        );
        return _SpeciesStageRunnerDiagnostics(
          anyImageDownloaded: summary.imageCount > 0,
        );
      },
    );
  }

  Future<_StageRunOutcome> _runCommonNameStage(
    String deckId,
    EnrichmentJobPayload payload, {
    required bool captureCompletionSummary,
    required String owner,
    required Future<bool> Function() shouldCancel,
  }) async {
    final speciesOutcome = await _runSpeciesStageWithCheckpoint(
      deckId,
      payload,
      stage: EnrichmentStage.names,
      captureCompletionSummary: captureCompletionSummary,
      owner: owner,
      shouldCancel: shouldCancel,
      batchSize: _namesBatchSize,
      runner: (remainingSpeciesIds, onSpeciesCompleted) async {
        _log.debug(
          'Run species names stage deck=$deckId '
          'species=${remainingSpeciesIds.length}',
        );
        CommonNameStageDiagnostics? diagnostics;
        await _enrichmentService.fetchSpeciesCommonNamesForSpecies(
          remainingSpeciesIds,
          maxConcurrent: backgroundINatMaxConcurrent,
          requestSpacing: backgroundINatRequestSpacing,
          onSpeciesCompleted: onSpeciesCompleted,
          onDiagnostics: captureCompletionSummary
              ? (value) => diagnostics = value
              : null,
        );
        if (diagnostics == null) {
          return null;
        }
        return _SpeciesStageRunnerDiagnostics(
          speciesIdsWithRemainingErrors:
              diagnostics!.speciesIdsWithRemainingErrors,
        );
      },
    );
    if (!speciesOutcome.completedStage) {
      return speciesOutcome;
    }
    return _runTaxonomyCommonNameStage(
      deckId,
      speciesOutcome.payload,
      captureCompletionSummary: captureCompletionSummary,
      owner: owner,
      shouldCancel: shouldCancel,
    );
  }

  Future<_StageRunOutcome> _runBackfillINatStage(
    String deckId,
    EnrichmentJobPayload payload, {
    required bool captureCompletionSummary,
    required String owner,
    required Future<bool> Function() shouldCancel,
  }) async {
    return _runSpeciesStageWithCheckpoint(
      deckId,
      payload,
      stage: EnrichmentStage.inatBackfill,
      captureCompletionSummary: captureCompletionSummary,
      owner: owner,
      shouldCancel: shouldCancel,
      batchSize: _backfillINatBatchSize,
      runner: (remainingSpeciesIds, onSpeciesCompleted) async {
        _log.debug(
          'Run iNat backfill stage deck=$deckId species=${remainingSpeciesIds.length}',
        );
        await _enrichmentService.backfillINatPhotosForSpecies(
          remainingSpeciesIds,
          maxConcurrent: backgroundINatMaxConcurrent,
          requestSpacing: backgroundINatRequestSpacing,
          onSpeciesCompleted: onSpeciesCompleted,
        );
        return null;
      },
    );
  }

  Future<_StageRunOutcome> _runSpeciesStageWithCheckpoint(
    String deckId,
    EnrichmentJobPayload payload, {
    required EnrichmentStage stage,
    required bool captureCompletionSummary,
    required String owner,
    required Future<bool> Function() shouldCancel,
    required int batchSize,
    required Future<_SpeciesStageRunnerDiagnostics?> Function(
      Set<String> remainingSpeciesIds,
      void Function(String speciesId) onSpeciesCompleted,
    )
    runner,
  }) async {
    // This is the central checkpointed stage runner for species-by-species
    // enrichment work.
    //
    // The important contract is: `onSpeciesCompleted` must only be called when
    // the species has reached a *terminal* state for this stage.
    //
    // "Terminal" means one of two things:
    // 1. the enrichment data was actually written successfully, or
    // 2. we stored an explicit no-result marker (for example "__empty__" in
    //    the iNat photo cache, or the runtime common-name no-result marker).
    //
    // We intentionally do *not* auto-complete species just because the runner
    // loop touched them once. Earlier versions did exactly that, which caused
    // subtle false-success bugs: transient lookup failures or taxonomy/name
    // mismatches could leave a species without iNat data while the stage was
    // still marked `succeeded` and the deck banner disappeared.
    //
    // Keeping the remaining species in the checkpoint payload means the queue
    // can yield and retry later instead of silently declaring success.
    final allSpeciesIds = orderedUniqueStrings(payload.speciesIds);
    if (allSpeciesIds.isEmpty) {
      _log.debug('Skip ${stage.name} stage deck=$deckId no species');
      return _StageRunOutcome.completed(
        payload: payload,
        completed: 0,
        total: 0,
      );
    }

    final initialCheckpointIds =
        payload
            .remainingSpeciesIdsForStage(stage)
            ?.where((speciesId) => allSpeciesIds.contains(speciesId))
            .toList(growable: false) ??
        allSpeciesIds;
    // Defensive de-duplication across decks: if another deck has already
    // succeeded for this species/stage, skip it locally. Catches races and
    // ensures correctness even if the ownership assignment was not perfectly
    // partitioned (e.g. mid-flight import that races against an in-flight run).
    final globallySucceeded =
        await _workRepository.loadSucceededSpeciesIdsForStage(stage);
    final checkpointSpeciesIds = globallySucceeded.isEmpty
        ? initialCheckpointIds
        : initialCheckpointIds
              .where((speciesId) => !globallySucceeded.contains(speciesId))
              .toList(growable: false);
    if (checkpointSpeciesIds.length != initialCheckpointIds.length) {
      _log.debug(
        'Skip already-succeeded species deck=$deckId stage=${stage.name} '
        'skipped=${initialCheckpointIds.length - checkpointSpeciesIds.length}',
      );
    }
    final remainingSpeciesIds = List<String>.from(checkpointSpeciesIds);
    final remainingSpeciesIdSet = checkpointSpeciesIds.toSet();
    var currentPayload = payload.copyWithRemainingSpeciesIds(
      stage,
      checkpointSpeciesIds.isEmpty ? null : checkpointSpeciesIds,
    );
    final total = allSpeciesIds.length;
    final batchSpeciesIds = checkpointSpeciesIds.take(batchSize).toSet();

    await _jobRepository.updateStageCheckpoint(
      deckId: deckId,
      owner: owner,
      payload: currentPayload,
      completed: total - remainingSpeciesIdSet.length,
      total: total,
    );
    if (_onStateChanged != null) {
      await _onStateChanged();
    }
    if (await shouldCancel()) {
      return _StageRunOutcome.completed(
        payload: currentPayload,
        completed: total - remainingSpeciesIdSet.length,
        total: total,
      );
    }

    Future<void> checkpointWrites = Future.value();
    final pendingCheckpointIds = <String>[];

    void flushCheckpoint() {
      if (pendingCheckpointIds.isEmpty) return;
      final flushedIds = Set<String>.from(pendingCheckpointIds);
      pendingCheckpointIds.clear();
      final payloadSnapshot = currentPayload;
      final completedSnapshot = total - remainingSpeciesIdSet.length;
      checkpointWrites = checkpointWrites.then((_) async {
        await _workRepository.markSpeciesStageCompleted(
          stage: stage,
          speciesIds: flushedIds,
        );
        await _jobRepository.updateStageCheckpoint(
          deckId: deckId,
          owner: owner,
          payload: payloadSnapshot,
          completed: completedSnapshot,
          total: total,
        );
        if (_onStateChanged != null) {
          await _onStateChanged();
        }
      });
    }

    void onSpeciesCompleted(String speciesId) {
      if (!remainingSpeciesIdSet.remove(speciesId)) return;
      remainingSpeciesIds.remove(speciesId);
      currentPayload = currentPayload
          .copyWithRemainingSpeciesIds(
            stage,
            remainingSpeciesIds.isEmpty ? null : remainingSpeciesIds,
          )
          .copyWithoutSpeciesStageAttemptCount(stage, speciesId);
      pendingCheckpointIds.add(speciesId);
      if (pendingCheckpointIds.length >= _checkpointFlushSize) {
        flushCheckpoint();
      }
    }

    _SpeciesStageRunnerDiagnostics? runnerDiagnostics;
    try {
      runnerDiagnostics = await runner(batchSpeciesIds, onSpeciesCompleted);
    } catch (_) {
      flushCheckpoint();
      await checkpointWrites;
      rethrow;
    }
    flushCheckpoint();
    await checkpointWrites;

    // Species the runner just touched (were in this run's batch) but did not
    // complete get an attempt recorded. EnrichmentService intentionally
    // swallows per-species errors so one broken species doesn't block the
    // rest of the batch, so this loop — not a thrown exception — is what
    // eventually gives up on a persistently failing species. See
    // _maxSpeciesStageAttempts.
    final attemptedThisRun = batchSpeciesIds.where(
      remainingSpeciesIdSet.contains,
    );
    if (attemptedThisRun.isNotEmpty) {
      final attemptCounts = Map<String, int>.from(
        currentPayload.speciesStageAttemptCounts[stage.name] ?? const {},
      );
      final givenUpSpeciesIds = <String>[];
      for (final speciesId in attemptedThisRun) {
        final attempts = (attemptCounts[speciesId] ?? 0) + 1;
        if (attempts >= _maxSpeciesStageAttempts) {
          givenUpSpeciesIds.add(speciesId);
        } else {
          attemptCounts[speciesId] = attempts;
        }
      }
      currentPayload = currentPayload.copyWithSpeciesStageAttemptCounts(
        stage,
        attemptCounts,
      );
      if (givenUpSpeciesIds.isNotEmpty) {
        _log.warn(
          'Giving up on ${givenUpSpeciesIds.length} species for stage '
          '${stage.name} deck=$deckId after $_maxSpeciesStageAttempts '
          'attempts without a terminal outcome: $givenUpSpeciesIds',
        );
        for (final speciesId in givenUpSpeciesIds) {
          onSpeciesCompleted(speciesId);
        }
        flushCheckpoint();
        await checkpointWrites;
      }
    }

    if (runnerDiagnostics?.anyImageDownloaded == true &&
        !currentPayload.hasAnyImage) {
      currentPayload = currentPayload.copyWith(hasAnyImage: true);
    }
    final completed = total - remainingSpeciesIdSet.length;
    final completionSummary = captureCompletionSummary
        ? SpeciesStageCompletionSummary(
            stage: stage,
            plannedSpeciesIds: allSpeciesIds.toSet(),
            completedSpeciesIds: allSpeciesIds
                .where(
                  (speciesId) => !remainingSpeciesIdSet.contains(speciesId),
                )
                .toSet(),
            speciesIdsWithRemainingErrors:
                runnerDiagnostics?.speciesIdsWithRemainingErrors ?? const {},
          )
        : null;
    if (remainingSpeciesIdSet.isNotEmpty) {
      return _StageRunOutcome.yielded(
        payload: currentPayload,
        completed: completed,
        total: total,
        completionSummary: completionSummary,
      );
    }
    return _StageRunOutcome.completed(
      payload: currentPayload,
      completed: completed,
      total: total,
      completionSummary: completionSummary,
    );
  }

  Future<_StageRunOutcome> _runTaxonomyCommonNameStage(
    String deckId,
    EnrichmentJobPayload payload, {
    required bool captureCompletionSummary,
    required String owner,
    required Future<bool> Function() shouldCancel,
  }) async {
    final allSpeciesIds = orderedUniqueStrings(payload.speciesIds);
    if (allSpeciesIds.isEmpty) {
      return _StageRunOutcome.completed(
        payload: payload,
        completed: 0,
        total: 0,
      );
    }

    final existingCheckpoint = payload.remainingTaxonomyEntityKeysForStage(
      EnrichmentStage.names,
    );
    final plannedTaxonomyItems = await _workRepository.assignTaxonomyOwners(
      deckId: deckId,
      items: await _taxonomyEnrichmentService.buildTaxonomyWorkPlanForSpecies(
        allSpeciesIds.toSet(),
      ),
    );
    final allEntityKeys =
        existingCheckpoint ??
        plannedTaxonomyItems
            .map((item) => item.runtimeEntityKey)
            .toList(growable: false);
    if (allEntityKeys.isEmpty) {
      return _StageRunOutcome.completed(
        payload: payload.copyWithRemainingTaxonomyEntityKeys(
          EnrichmentStage.names,
          null,
        ),
        completed: allSpeciesIds.length,
        total: allSpeciesIds.length,
        completionSummary: captureCompletionSummary
            ? SpeciesStageCompletionSummary(
                stage: EnrichmentStage.names,
                plannedSpeciesIds: allSpeciesIds.toSet(),
                completedSpeciesIds: allSpeciesIds.toSet(),
                speciesIdsWithRemainingErrors: const <String>{},
              )
            : null,
      );
    }

    final remainingEntityKeys = List<String>.from(allEntityKeys);
    final remainingEntityKeySet = remainingEntityKeys.toSet();
    var currentPayload = payload.copyWithRemainingTaxonomyEntityKeys(
      EnrichmentStage.names,
      remainingEntityKeys,
    );
    final total = allSpeciesIds.length;

    await _jobRepository.updateStageCheckpoint(
      deckId: deckId,
      owner: owner,
      payload: currentPayload,
      completed: total,
      total: total,
    );
    if (_onStateChanged != null) {
      await _onStateChanged();
    }
    if (await shouldCancel()) {
      return _StageRunOutcome.completed(
        payload: currentPayload,
        completed: total,
        total: total,
      );
    }

    final batchEntityKeys = remainingEntityKeys
        .take(_namesBatchSize)
        .toList(growable: false);
    final workKeyByRuntimeEntityKey = {
      for (final item in plannedTaxonomyItems)
        item.runtimeEntityKey: item.workKey,
    };
    Future<void> checkpointWrites = Future.value();

    void onEntityCompleted(String entityKey) {
      if (!remainingEntityKeySet.remove(entityKey)) {
        return;
      }
      remainingEntityKeys.remove(entityKey);
      currentPayload = currentPayload.copyWithRemainingTaxonomyEntityKeys(
        EnrichmentStage.names,
        remainingEntityKeys.isEmpty ? null : remainingEntityKeys,
      );
      final payloadSnapshot = currentPayload;
      final workKey = workKeyByRuntimeEntityKey[entityKey];
      checkpointWrites = checkpointWrites.then((_) async {
        if (workKey != null) {
          await _workRepository.markTaxonomyCommonNamesCompleted({workKey});
        }
        await _jobRepository.updateStageCheckpoint(
          deckId: deckId,
          owner: owner,
          payload: payloadSnapshot,
          completed: total,
          total: total,
        );
        if (_onStateChanged != null) {
          await _onStateChanged();
        }
      });
    }

    _SpeciesStageRunnerDiagnostics? diagnostics;
    try {
      await _taxonomyEnrichmentService.fetchINatTaxonomyCommonNamesForEntityKeys(
        allSpeciesIds.toSet(),
        entityKeys: batchEntityKeys,
        maxConcurrent: backgroundINatMaxConcurrent,
        requestSpacing: backgroundINatRequestSpacing,
        isCancelled: () => false,
        onEntityCompleted: onEntityCompleted,
        onDiagnostics: captureCompletionSummary
            ? (value) {
                diagnostics = _SpeciesStageRunnerDiagnostics(
                  speciesIdsWithRemainingErrors:
                      value.speciesIdsWithRemainingErrors,
                );
              }
            : null,
      );
    } catch (_) {
      await checkpointWrites;
      rethrow;
    }
    await checkpointWrites;

    final completionSummary = captureCompletionSummary
        ? SpeciesStageCompletionSummary(
            stage: EnrichmentStage.names,
            plannedSpeciesIds: allSpeciesIds.toSet(),
            completedSpeciesIds: allSpeciesIds.toSet(),
            speciesIdsWithRemainingErrors:
                diagnostics?.speciesIdsWithRemainingErrors ?? const {},
          )
        : null;
    if (remainingEntityKeys.isNotEmpty) {
      return _StageRunOutcome.yielded(
        payload: currentPayload,
        completed: total,
        total: total,
        completionSummary: completionSummary,
      );
    }
    return _StageRunOutcome.completed(
      payload: currentPayload,
      completed: total,
      total: total,
      completionSummary: completionSummary,
    );
  }
}

class _StageRunOutcome {
  final EnrichmentJobPayload payload;
  final bool completedStage;
  final int completed;
  final int total;
  final SpeciesStageCompletionSummary? completionSummary;

  const _StageRunOutcome.completed({
    required this.payload,
    required this.completed,
    required this.total,
    this.completionSummary,
  }) : completedStage = true;

  const _StageRunOutcome.yielded({
    required this.payload,
    required this.completed,
    required this.total,
    this.completionSummary,
  }) : completedStage = false;
}

Set<String> _speciesIdsForStage(
  EnrichmentJobPayload payload,
  EnrichmentStage stage,
) {
  switch (stage) {
    case EnrichmentStage.base:
    case EnrichmentStage.inatPrimary:
    case EnrichmentStage.names:
    case EnrichmentStage.inatBackfill:
      return payload.remainingSpeciesIdsForStage(stage)?.toSet() ??
          payload.speciesIds.toSet();
    case EnrichmentStage.nameResolution:
    case EnrichmentStage.cover:
      return const <String>{};
  }
}

class _SpeciesStageRunnerDiagnostics {
  final Set<String> speciesIdsWithRemainingErrors;
  final bool anyImageDownloaded;

  const _SpeciesStageRunnerDiagnostics({
    this.speciesIdsWithRemainingErrors = const <String>{},
    this.anyImageDownloaded = false,
  });
}
