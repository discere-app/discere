import 'dart:async';

import 'package:discere/enrichment/repository/enrichment_job_repository.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:discere/shared/service/local_diagnostics.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:http/http.dart' as http;

import 'enrichment_job_ports.dart';
import 'enrichment_service.dart';

enum EnrichmentFailureKind { temporary, permanent }

class EnrichmentJobExecutor {
  static final _log = Logger.forType(EnrichmentJobExecutor);
  static const backgroundINatMaxConcurrent = 1;
  static const backgroundINatRequestSpacing = Duration(milliseconds: 1100);
  static const _baseStageBatchSize = 25;
  static const _primaryINatBatchSize = 12;
  static const _namesBatchSize = 12;
  static const _backfillINatBatchSize = 8;

  final EnrichmentService _enrichmentService;
  final EnrichmentJobRepository _jobRepository;
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
    required DeckCoverStorePort deckCoverStore,
    required ImageService imageService,
    ScientificNameResolutionPort? nameResolutionPort,
    DeckSpeciesMutationPort? deckSpeciesMutationPort,
    UnresolvedNamesObserverPort? unresolvedNamesObserver,
    Future<void> Function()? onStateChanged,
    LocalDiagnostics? diagnostics,
  }) : _deckCoverStore = deckCoverStore,
       _imageService = imageService,
       _nameResolutionPort = nameResolutionPort,
       _deckSpeciesMutationPort = deckSpeciesMutationPort,
       _unresolvedNamesObserver = unresolvedNamesObserver,
       _onStateChanged = onStateChanged,
       _diagnostics = diagnostics ?? LocalDiagnostics.instance;

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
          },
        );
        if (_onStateChanged != null) {
          await _onStateChanged();
        }
      } catch (error) {
        stageStopwatch.stop();
        final failureKind = _classifyFailure(error);
        if (failureKind == EnrichmentFailureKind.temporary) {
          await _jobRepository.markStageRetryScheduled(
            deckId: job.deckId,
            stage: stage,
            owner: owner,
            error: error.toString(),
            failureKind: failureKind.name,
          );
        } else {
          await _jobRepository.markStageFailedPermanent(
            deckId: job.deckId,
            stage: stage,
            owner: owner,
            error: error.toString(),
            failureKind: failureKind.name,
          );
        }
        await _diagnostics.recordEvent(
          category: 'enrichment',
          eventType: failureKind == EnrichmentFailureKind.temporary
              ? 'stage_retry_scheduled'
              : 'stage_failed_permanent',
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
        'pendingWork': await _jobRepository.hasPendingWork(),
      },
    );
    return processedAny;
  }

  Future<_StageRunOutcome> _runStage(
    String deckId,
    EnrichmentJobPayload payload,
    EnrichmentStage stage, {
    required String owner,
    required Future<bool> Function() shouldCancel,
  }) async {
    switch (stage) {
      case EnrichmentStage.nameResolution:
        return _runNameResolutionStage(
          deckId,
          payload,
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
          owner: owner,
          shouldCancel: shouldCancel,
        );
      case EnrichmentStage.inatPrimary:
        return _runPrimaryINatStage(
          deckId,
          payload,
          owner: owner,
          shouldCancel: shouldCancel,
        );
      case EnrichmentStage.names:
        return _runCommonNameStage(
          deckId,
          payload,
          owner: owner,
          shouldCancel: shouldCancel,
        );
      case EnrichmentStage.inatBackfill:
        return _runBackfillINatStage(
          deckId,
          payload,
          owner: owner,
          shouldCancel: shouldCancel,
        );
    }
  }

  Future<_StageRunOutcome> _runNameResolutionStage(
    String deckId,
    EnrichmentJobPayload payload, {
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
    required String owner,
    required Future<bool> Function() shouldCancel,
  }) async {
    return _runSpeciesStageWithCheckpoint(
      deckId,
      payload,
      stage: EnrichmentStage.base,
      owner: owner,
      shouldCancel: shouldCancel,
      batchSize: _baseStageBatchSize,
      runner: (remainingSpeciesIds, onSpeciesCompleted) async {
        _log.debug(
          'Run base stage deck=$deckId species=${remainingSpeciesIds.length}',
        );
        await _enrichmentService.downloadBaseImagesForSpecies(
          remainingSpeciesIds,
          onSpeciesCompleted: onSpeciesCompleted,
        );
      },
    );
  }

  Future<_StageRunOutcome> _runPrimaryINatStage(
    String deckId,
    EnrichmentJobPayload payload, {
    required String owner,
    required Future<bool> Function() shouldCancel,
  }) async {
    return _runSpeciesStageWithCheckpoint(
      deckId,
      payload,
      stage: EnrichmentStage.inatPrimary,
      owner: owner,
      shouldCancel: shouldCancel,
      batchSize: _primaryINatBatchSize,
      runner: (remainingSpeciesIds, onSpeciesCompleted) async {
        _log.debug(
          'Run iNat primary stage deck=$deckId species=${remainingSpeciesIds.length}',
        );
        await _enrichmentService.fetchINatPhotosForSpecies(
          remainingSpeciesIds,
          primaryOnly: true,
          prioritizeSpeciesWithoutImages: true,
          maxConcurrent: backgroundINatMaxConcurrent,
          requestSpacing: backgroundINatRequestSpacing,
          onSpeciesCompleted: onSpeciesCompleted,
        );
      },
    );
  }

  Future<_StageRunOutcome> _runCommonNameStage(
    String deckId,
    EnrichmentJobPayload payload, {
    required String owner,
    required Future<bool> Function() shouldCancel,
  }) async {
    return _runSpeciesStageWithCheckpoint(
      deckId,
      payload,
      stage: EnrichmentStage.names,
      owner: owner,
      shouldCancel: shouldCancel,
      batchSize: _namesBatchSize,
      runner: (remainingSpeciesIds, onSpeciesCompleted) async {
        _log.debug(
          'Run names stage deck=$deckId species=${remainingSpeciesIds.length}',
        );
        await _enrichmentService.fetchINatCommonNamesForSpecies(
          remainingSpeciesIds,
          maxConcurrent: backgroundINatMaxConcurrent,
          requestSpacing: backgroundINatRequestSpacing,
          onSpeciesCompleted: onSpeciesCompleted,
        );
      },
    );
  }

  Future<_StageRunOutcome> _runBackfillINatStage(
    String deckId,
    EnrichmentJobPayload payload, {
    required String owner,
    required Future<bool> Function() shouldCancel,
  }) async {
    return _runSpeciesStageWithCheckpoint(
      deckId,
      payload,
      stage: EnrichmentStage.inatBackfill,
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
      },
    );
  }

  Future<_StageRunOutcome> _runSpeciesStageWithCheckpoint(
    String deckId,
    EnrichmentJobPayload payload, {
    required EnrichmentStage stage,
    required String owner,
    required Future<bool> Function() shouldCancel,
    required int batchSize,
    required Future<void> Function(
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
    final allSpeciesIds = payload.speciesIds.toSet().toList()..sort();
    if (allSpeciesIds.isEmpty) {
      _log.debug('Skip ${stage.name} stage deck=$deckId no species');
      return _StageRunOutcome.completed(
        payload: payload,
        completed: 0,
        total: 0,
      );
    }

    final checkpointSpeciesIds =
        payload.remainingSpeciesIdsForStage(stage)?.toSet().toList() ??
        allSpeciesIds;
    checkpointSpeciesIds.sort();
    final remainingSpeciesIds = checkpointSpeciesIds.toSet();
    var currentPayload = payload.copyWithRemainingSpeciesIds(
      stage,
      checkpointSpeciesIds,
    );
    final total = allSpeciesIds.length;
    final batchSpeciesIds = checkpointSpeciesIds.take(batchSize).toSet();

    await _jobRepository.updateStageCheckpoint(
      deckId: deckId,
      owner: owner,
      payload: currentPayload,
      completed: total - remainingSpeciesIds.length,
      total: total,
    );
    if (_onStateChanged != null) {
      await _onStateChanged();
    }
    if (await shouldCancel()) {
      return _StageRunOutcome.completed(
        payload: currentPayload,
        completed: total - remainingSpeciesIds.length,
        total: total,
      );
    }

    Future<void> checkpointWrites = Future.value();
    final completedInBatch = <String>{};

    void onSpeciesCompleted(String speciesId) {
      completedInBatch.add(speciesId);
      if (!remainingSpeciesIds.remove(speciesId)) return;
      currentPayload = currentPayload.copyWithRemainingSpeciesIds(
        stage,
        remainingSpeciesIds.toList()..sort(),
      );
      final payloadSnapshot = currentPayload;
      final completedSnapshot = total - remainingSpeciesIds.length;
      checkpointWrites = checkpointWrites.then((_) async {
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

    await runner(batchSpeciesIds, onSpeciesCompleted);
    await checkpointWrites;
    final completed = total - remainingSpeciesIds.length;
    if (remainingSpeciesIds.isNotEmpty) {
      return _StageRunOutcome.yielded(
        payload: currentPayload,
        completed: completed,
        total: total,
      );
    }
    return _StageRunOutcome.completed(
      payload: currentPayload,
      completed: completed,
      total: total,
    );
  }
}

class _StageRunOutcome {
  final EnrichmentJobPayload payload;
  final bool completedStage;
  final int completed;
  final int total;

  const _StageRunOutcome.completed({
    required this.payload,
    required this.completed,
    required this.total,
  }) : completedStage = true;

  const _StageRunOutcome.yielded({
    required this.payload,
    required this.completed,
    required this.total,
  }) : completedStage = false;
}

EnrichmentFailureKind _classifyFailure(Object error) {
  if (error is TimeoutException) return EnrichmentFailureKind.temporary;
  if (error is http.ClientException) return EnrichmentFailureKind.temporary;
  if (error is HttpDownloadException) {
    return error.isRetryable
        ? EnrichmentFailureKind.temporary
        : EnrichmentFailureKind.permanent;
  }
  return EnrichmentFailureKind.permanent;
}
