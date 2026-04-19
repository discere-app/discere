import 'dart:async';

import 'package:discere/enrichment/repository/enrichment_job_repository.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:http/http.dart' as http;

import 'enrichment_job_ports.dart';
import 'enrichment_service.dart';

enum EnrichmentFailureKind { temporary, permanent }

class EnrichmentJobExecutor {
  static final _log = Logger.forType(EnrichmentJobExecutor);
  static const backgroundINatMaxConcurrent = 1;
  static const backgroundINatRequestSpacing = Duration(milliseconds: 1100);

  final EnrichmentService _enrichmentService;
  final EnrichmentJobRepository _jobRepository;
  final DeckCoverStorePort _deckCoverStore;
  final ImageService _imageService;
  final ScientificNameResolutionPort? _nameResolutionPort;
  final DeckSpeciesMutationPort? _deckSpeciesMutationPort;
  final UnresolvedNamesObserverPort? _unresolvedNamesObserver;
  final Future<void> Function()? _onStateChanged;

  const EnrichmentJobExecutor(
    this._enrichmentService,
    this._jobRepository, {
    required DeckCoverStorePort deckCoverStore,
    required ImageService imageService,
    ScientificNameResolutionPort? nameResolutionPort,
    DeckSpeciesMutationPort? deckSpeciesMutationPort,
    UnresolvedNamesObserverPort? unresolvedNamesObserver,
    Future<void> Function()? onStateChanged,
  }) : _deckCoverStore = deckCoverStore,
       _imageService = imageService,
       _nameResolutionPort = nameResolutionPort,
       _deckSpeciesMutationPort = deckSpeciesMutationPort,
       _unresolvedNamesObserver = unresolvedNamesObserver,
       _onStateChanged = onStateChanged;

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
  }) async {
    var processedAny = false;
    for (var i = 0; i < maxStageRuns; i++) {
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
        'Execute stage deck=${job.deckId} stage=${stage.name} '
        'runner=${runnerKind.name} species=${job.payload.speciesIds.length} '
        'unresolved=${job.payload.unresolvedSpeciesNames.length}',
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
        final payload = await _runStage(
          job.deckId,
          job.payload,
          stage,
          shouldCancel: () async =>
              !(await _jobRepository.isJobActive(
                deckId: job.deckId,
                owner: owner,
              )),
        );
        await _jobRepository.markStageSucceeded(
          deckId: job.deckId,
          stage: stage,
          owner: owner,
          payload: payload,
        );
        _log.debug(
          'Stage success deck=${job.deckId} stage=${stage.name} '
          'runner=${runnerKind.name}',
        );
        if (_onStateChanged != null) {
          await _onStateChanged();
        }
      } catch (error) {
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
        _log.warn(
          'Enrichment failed for ${job.deckId} '
          '(${stage.name}, ${failureKind.name}): $error',
        );
        if (_onStateChanged != null) {
          await _onStateChanged();
        }
      }
    }
    return processedAny;
  }

  Future<EnrichmentJobPayload> _runStage(
    String deckId,
    EnrichmentJobPayload payload,
    EnrichmentStage stage, {
    required Future<bool> Function() shouldCancel,
  }
  ) async {
    switch (stage) {
      case EnrichmentStage.nameResolution:
        return _runNameResolutionStage(
          deckId,
          payload,
          shouldCancel: shouldCancel,
        );
      case EnrichmentStage.cover:
        await _runCoverStage(deckId, payload, shouldCancel: shouldCancel);
        return payload;
      case EnrichmentStage.base:
        await _runBaseStage(deckId, payload, shouldCancel: shouldCancel);
        return payload;
      case EnrichmentStage.inatPrimary:
        await _runPrimaryINatStage(
          deckId,
          payload,
          shouldCancel: shouldCancel,
        );
        return payload;
      case EnrichmentStage.names:
        await _runCommonNameStage(
          deckId,
          payload,
          shouldCancel: shouldCancel,
        );
        return payload;
      case EnrichmentStage.inatBackfill:
        await _runBackfillINatStage(
          deckId,
          payload,
          shouldCancel: shouldCancel,
        );
        return payload;
    }
  }

  Future<EnrichmentJobPayload> _runNameResolutionStage(
    String deckId,
    EnrichmentJobPayload payload, {
    required Future<bool> Function() shouldCancel,
  }
  ) async {
    final namesToResolve = payload.unresolvedSpeciesNames;
    if (namesToResolve.isEmpty ||
        _nameResolutionPort == null ||
        _deckSpeciesMutationPort == null) {
      _log.debug(
        'Skip name resolution deck=$deckId names=${namesToResolve.length} '
        'resolver=${_nameResolutionPort != null} mutation=${_deckSpeciesMutationPort != null}',
      );
      return payload.copyWith(stillUnresolvedNames: namesToResolve);
    }
    if (await shouldCancel()) return payload;

    await _reportProgress(
      deckId: deckId,
      completed: 0,
      total: namesToResolve.length,
    );

    final resolved = await _nameResolutionPort.resolveNames(namesToResolve);
    if (await shouldCancel()) return payload;
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

    return payload.copyWith(
      speciesIds: mergedSpeciesIds,
      stillUnresolvedNames: stillUnresolved,
    );
  }

  Future<void> _runCoverStage(
    String deckId,
    EnrichmentJobPayload payload, {
    required Future<bool> Function() shouldCancel,
  }
  ) async {
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

  Future<void> _runBaseStage(
    String deckId,
    EnrichmentJobPayload payload, {
    required Future<bool> Function() shouldCancel,
  }
  ) async {
    final speciesIds = payload.speciesIds.toSet();
    if (speciesIds.isEmpty) {
      _log.debug('Skip base stage deck=$deckId no species');
      return;
    }
    _log.debug('Run base stage deck=$deckId species=${speciesIds.length}');
    await _enrichmentService.downloadBaseImagesForSpecies(
      speciesIds,
      onProgress: (completed, total) {
        unawaited(
          _reportProgress(
            deckId: deckId,
            completed: completed,
            total: total,
          ),
        );
      },
    );
  }

  Future<void> _runPrimaryINatStage(
    String deckId,
    EnrichmentJobPayload payload, {
    required Future<bool> Function() shouldCancel,
  }
  ) async {
    final speciesIds = payload.speciesIds.toSet();
    if (speciesIds.isEmpty) {
      _log.debug('Skip iNat primary stage deck=$deckId no species');
      return;
    }
    _log.debug(
      'Run iNat primary stage deck=$deckId species=${speciesIds.length}',
    );
    await _enrichmentService.fetchINatPhotosForSpecies(
      speciesIds,
      primaryOnly: true,
      prioritizeSpeciesWithoutImages: true,
      maxConcurrent: backgroundINatMaxConcurrent,
      requestSpacing: backgroundINatRequestSpacing,
      onProgress: (completed, total) {
        unawaited(
          _reportProgress(
            deckId: deckId,
            completed: completed,
            total: total,
          ),
        );
      },
    );
  }

  Future<void> _runCommonNameStage(
    String deckId,
    EnrichmentJobPayload payload, {
    required Future<bool> Function() shouldCancel,
  }
  ) async {
    final speciesIds = payload.speciesIds.toSet();
    if (speciesIds.isEmpty) {
      _log.debug('Skip names stage deck=$deckId no species');
      return;
    }
    _log.debug('Run names stage deck=$deckId species=${speciesIds.length}');
    await _enrichmentService.fetchINatCommonNamesForSpecies(
      speciesIds,
      maxConcurrent: backgroundINatMaxConcurrent,
      requestSpacing: backgroundINatRequestSpacing,
      onProgress: (completed, total) {
        unawaited(
          _reportProgress(
            deckId: deckId,
            completed: completed,
            total: total,
          ),
        );
      },
    );
  }

  Future<void> _runBackfillINatStage(
    String deckId,
    EnrichmentJobPayload payload, {
    required Future<bool> Function() shouldCancel,
  }
  ) async {
    final speciesIds = payload.speciesIds.toSet();
    if (speciesIds.isEmpty) {
      _log.debug('Skip iNat backfill stage deck=$deckId no species');
      return;
    }
    _log.debug(
      'Run iNat backfill stage deck=$deckId species=${speciesIds.length}',
    );
    await _enrichmentService.backfillINatPhotosForSpecies(
      speciesIds,
      maxConcurrent: backgroundINatMaxConcurrent,
      requestSpacing: backgroundINatRequestSpacing,
      onProgress: (completed, total) {
        unawaited(
          _reportProgress(
            deckId: deckId,
            completed: completed,
            total: total,
          ),
        );
      },
    );
  }
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
