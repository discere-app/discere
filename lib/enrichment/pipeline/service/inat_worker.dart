import 'package:discere/diagnostics/service/local_diagnostics.dart';
import 'package:discere/enrichment/pipeline/model/inat_work_item.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_repository.dart';
import 'package:discere/enrichment/pipeline/repository/inat_photo_cache_repository.dart';
import 'package:discere/enrichment/pipeline/service/inat_photo_enrichment_service.dart';
import 'package:discere/enrichment/pipeline/service/species_common_name_enrichment_service.dart';
import 'package:discere/enrichment/pipeline/service/taxonomy_common_name_enrichment_service.dart';
import 'package:discere/enrichment/ports/enrichment_job_ports.dart';
import 'package:discere/enrichment/queue/model/enrichment_job.dart';
import 'package:discere/enrichment/queue/service/enrichment_failure_classifier.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:sqflite/sqflite.dart';

/// Drains the shared iNaturalist work queue (`inatPrimary`,
/// `speciesCommonNames`, `taxonomyCommonNames`, `inatBackfill`,
/// `nameResolution` — see [INatWorkItemKind]) one item at a time, respecting
/// iNaturalist's rate limit with a fixed spacing between claims.
///
/// This is the other half of the producer-consumer enrichment pipeline (see
/// the enrichment-optimization plan / GitHub issues #56, #57) — [INatWorker]
/// and `BaseWorker` are two independently-scheduled loops sharing the queue
/// tables in [EnrichmentWorkRepository]. Name resolution is folded into this
/// same consumer (at the lowest priority tier) rather than running as its
/// own unthrottled path, so "one rate-limited iNat consumer" stays a real
/// invariant instead of two paths that could independently overload the API.
class INatWorker {
  static final _log = Logger.forType(INatWorker);

  /// Spacing between claims, matching iNaturalist's request budget.
  static const _requestSpacing = Duration(milliseconds: 1100);

  /// After this many failed attempts at an item, give up (permanent
  /// failure) instead of retrying forever — same budget as `BaseWorker`.
  static const _maxAttempts = 5;

  static const _retryBackoffSteps = [
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 2),
    Duration(minutes: 4),
  ];

  static const _inatBackfillPriorityTier = 40;

  /// Defensive circuit breaker against an unbounded loop.
  static const _maxIterations = 2000;

  final INatPhotoEnrichmentService _photoEnrichmentService;
  final SpeciesCommonNameEnrichmentService _commonNameEnrichmentService;
  final TaxonomyCommonNameEnrichmentService _taxonomyEnrichmentService;
  final EnrichmentWorkRepository _workRepository;
  final INatPhotoCacheRepository _photoCacheRepository;
  final LocalDiagnostics _diagnostics;
  final ScientificNameResolutionPort? _nameResolutionPort;
  final DeckSpeciesMutationPort? _deckSpeciesMutationPort;
  final UnresolvedNamesObserverPort? _unresolvedNamesObserver;

  const INatWorker(
    this._photoEnrichmentService,
    this._commonNameEnrichmentService,
    this._taxonomyEnrichmentService,
    this._workRepository,
    this._photoCacheRepository, {
    required LocalDiagnostics diagnostics,
    ScientificNameResolutionPort? nameResolutionPort,
    DeckSpeciesMutationPort? deckSpeciesMutationPort,
    UnresolvedNamesObserverPort? unresolvedNamesObserver,
  }) : _diagnostics = diagnostics,
       _nameResolutionPort = nameResolutionPort,
       _deckSpeciesMutationPort = deckSpeciesMutationPort,
       _unresolvedNamesObserver = unresolvedNamesObserver;

  /// Repeatedly claims and processes single work items — spaced by
  /// [_requestSpacing] — until either the queue is drained or [shouldStop]
  /// returns true. Returns whether any work was actually processed.
  Future<bool> runUntilIdle({required bool Function() shouldStop}) async {
    var processedAny = false;
    var isFirst = true;
    try {
      for (var iteration = 0; iteration < _maxIterations; iteration++) {
        if (shouldStop()) break;
        if (!isFirst) {
          await Future.delayed(_requestSpacing);
          if (shouldStop()) break;
        }
        isFirst = false;

        final item = await _workRepository.claimNextINatWorkItem();
        if (item == null) break;
        processedAny = true;
        _log.debug('Claimed iNat work item: $item');
        await _process(item);
      }
    } on DatabaseException {
      // The user DB was closed while this loop was in flight (app shutdown,
      // or - in integration tests - the next test's teardown deleting it out
      // from under a still-running worker). Nothing left to claim or write
      // retry/terminal bookkeeping against, so stop the loop instead of
      // throwing.
    }
    return processedAny;
  }

  Future<void> _process(INatWorkItem item) async {
    switch (item.kind) {
      case INatWorkItemKind.inatPrimary:
        await _processPrimaryPhoto(item.speciesId!);
      case INatWorkItemKind.speciesCommonNames:
        await _processSpeciesCommonNames(item.speciesId!);
      case INatWorkItemKind.inatBackfill:
        await _processBackfillPhoto(item.speciesId!);
      case INatWorkItemKind.taxonomyCommonNames:
        await _processTaxonomyCommonNames(item);
      case INatWorkItemKind.nameResolution:
        await _processNameResolution(item);
    }
  }

  Future<void> _processPrimaryPhoto(String speciesId) async {
    try {
      var terminal = false;
      await _photoEnrichmentService.fetchINatPhotosForSpecies(
        {speciesId},
        primaryOnly: true,
        onSpeciesCompleted: (_) => terminal = true,
      );
      if (!terminal) {
        await _retryOrFail(
          speciesId,
          EnrichmentStage.inatPrimary,
          error: 'iNat primary photo fetch did not complete',
          failureKind: EnrichmentFailureKind.temporary,
        );
        return;
      }
      final cachedPhotos = await _photoCacheRepository.getCachedPhotos(
        speciesId,
      );
      final state = (cachedPhotos != null && cachedPhotos.isNotEmpty)
          ? 'done'
          : 'noResult';
      await _workRepository.markCapabilityTerminal(
        speciesId,
        EnrichmentStage.inatPrimary,
        state,
      );
      // Whether or not a primary photo was actually found, the species now
      // has a stable resolution outcome — seed backfill (a no-op fetch for
      // species confirmed to have no photos, since INatPhotoEnrichmentService
      // itself treats that as terminal-skip) and taxonomy common names.
      await _workRepository.seedCapability(
        speciesId,
        EnrichmentStage.inatBackfill,
        priorityTier: _inatBackfillPriorityTier,
      );
      await _seedTaxonomyWorkForSpecies(speciesId);
      await _workRepository.pruneSpeciesMembershipIfFullyTerminal(speciesId);
    } catch (error) {
      _log.warn('iNat primary photo fetch failed for $speciesId: $error');
      await _retryOrFail(
        speciesId,
        EnrichmentStage.inatPrimary,
        error: error.toString(),
        failureKind: classifyEnrichmentFailure(error),
      );
    }
  }

  Future<void> _processBackfillPhoto(String speciesId) async {
    try {
      var terminal = false;
      await _photoEnrichmentService.backfillINatPhotosForSpecies({
        speciesId,
      }, onSpeciesCompleted: (_) => terminal = true);
      if (!terminal) {
        await _retryOrFail(
          speciesId,
          EnrichmentStage.inatBackfill,
          error: 'iNat backfill fetch did not complete',
          failureKind: EnrichmentFailureKind.temporary,
        );
        return;
      }
      // Backfill never gates deck readiness (only base/inatPrimary do) and
      // is a best-effort "more photos" capability, so there's no separate
      // no-result outcome worth tracking here — always 'done' once resolved.
      await _workRepository.markCapabilityTerminal(
        speciesId,
        EnrichmentStage.inatBackfill,
        'done',
      );
      await _workRepository.pruneSpeciesMembershipIfFullyTerminal(speciesId);
    } catch (error) {
      _log.warn('iNat backfill fetch failed for $speciesId: $error');
      await _retryOrFail(
        speciesId,
        EnrichmentStage.inatBackfill,
        error: error.toString(),
        failureKind: classifyEnrichmentFailure(error),
      );
    }
  }

  Future<void> _processSpeciesCommonNames(String speciesId) async {
    try {
      var terminal = false;
      await _commonNameEnrichmentService.fetchSpeciesCommonNamesForSpecies({
        speciesId,
      }, onSpeciesCompleted: (_) => terminal = true);
      if (!terminal) {
        await _retryOrFail(
          speciesId,
          EnrichmentStage.names,
          error: 'iNat common-name fetch did not complete',
          failureKind: EnrichmentFailureKind.temporary,
        );
        return;
      }
      // RuntimeCommonNameRepository has no way to distinguish "real names
      // found" from "confirmed empty" from the outside — the no-result
      // sentinel is stored as an ordinary row in the same table it checks
      // for "has any common name" — so both outcomes are equally terminal
      // here; always 'done' once resolved.
      await _workRepository.markCapabilityTerminal(
        speciesId,
        EnrichmentStage.names,
        'done',
      );
      await _seedTaxonomyWorkForSpecies(speciesId);
      await _workRepository.pruneSpeciesMembershipIfFullyTerminal(speciesId);
    } catch (error) {
      _log.warn('iNat common-name fetch failed for $speciesId: $error');
      await _retryOrFail(
        speciesId,
        EnrichmentStage.names,
        error: error.toString(),
        failureKind: classifyEnrichmentFailure(error),
      );
    }
  }

  Future<void> _processTaxonomyCommonNames(INatWorkItem item) async {
    final workKey = item.taxonomyWorkKey!;
    final runtimeEntityKey = item.taxonomyRuntimeEntityKey!;
    final speciesIds = item.taxonomySpeciesIds!;
    try {
      var terminal = false;
      await _taxonomyEnrichmentService
          .fetchINatTaxonomyCommonNamesForEntityKeys(
            speciesIds,
            entityKeys: [runtimeEntityKey],
            onEntityCompleted: (_) => terminal = true,
          );
      if (!terminal) {
        await _retryOrFailTaxonomy(
          workKey,
          error: 'iNat taxonomy common-name fetch did not complete',
          failureKind: EnrichmentFailureKind.temporary,
        );
        return;
      }
      await _workRepository.markTaxonomyCapabilityTerminal(workKey, 'done');
    } catch (error) {
      _log.warn('iNat taxonomy common-name fetch failed for $workKey: $error');
      await _retryOrFailTaxonomy(
        workKey,
        error: error.toString(),
        failureKind: classifyEnrichmentFailure(error),
      );
    }
  }

  Future<void> _processNameResolution(INatWorkItem item) async {
    final deckId = item.deckId!;
    final name = item.unresolvedName!;
    final nameResolutionPort = _nameResolutionPort;
    if (nameResolutionPort == null) {
      // No resolver wired at all — nothing more can ever happen for this
      // name, so don't leave it retrying forever.
      await _workRepository.deleteUnresolvedName(deckId, name);
      return;
    }
    try {
      final resolved = await nameResolutionPort.resolveNames([name]);
      final speciesId = resolved[name];
      if (speciesId == null) {
        final gaveUp = await _workRepository.recordUnresolvedNameAttemptFailure(
          deckId,
          name,
          maxAttempts: _maxAttempts,
          backoffSteps: _retryBackoffSteps,
          error: 'iNat name resolution did not resolve "$name"',
        );
        await _diagnostics.recordEvent(
          category: 'enrichment',
          eventType: gaveUp
              ? 'capability_failed_permanent'
              : 'capability_retry_scheduled',
          subjectType: 'unresolvedName',
          subjectId: '$deckId:$name',
          level: 'warning',
          message: 'iNat name resolution did not resolve "$name"',
          details: {'capability': 'nameResolution'},
        );
        if (gaveUp) {
          _unresolvedNamesObserver?.onNamesUnresolved(deckId, [name]);
        }
        return;
      }
      await _deckSpeciesMutationPort?.addSpeciesToDeck(deckId, {speciesId});
      // The "straggler round": register just this one species with exactly
      // the consent this name was submitted under (see INatWorkItem's doc
      // comment) — additive, so it merges into whatever else already
      // tracks this species instead of overwriting it.
      await _workRepository.registerResolvedSpeciesForDeck(
        speciesId,
        deckId,
        wantsInatPhotos: item.wantsInatPhotos,
        wantsCommonNames: item.wantsCommonNames,
      );
      await _workRepository.deleteUnresolvedName(deckId, name);
    } catch (error) {
      _log.warn('iNat name resolution failed for "$name": $error');
      final gaveUp = await _workRepository.recordUnresolvedNameAttemptFailure(
        deckId,
        name,
        maxAttempts: _maxAttempts,
        backoffSteps: _retryBackoffSteps,
        error: error.toString(),
      );
      await _diagnostics.recordEvent(
        category: 'enrichment',
        eventType: gaveUp
            ? 'capability_failed_permanent'
            : 'capability_retry_scheduled',
        subjectType: 'unresolvedName',
        subjectId: '$deckId:$name',
        level: 'warning',
        message: error.toString(),
        details: {
          'capability': 'nameResolution',
          'failureKind': classifyEnrichmentFailure(error).name,
        },
      );
    }
  }

  Future<void> _seedTaxonomyWorkForSpecies(String speciesId) async {
    final workPlan = await _taxonomyEnrichmentService
        .buildTaxonomyWorkPlanForSpecies({speciesId});
    if (workPlan.isEmpty) return;
    // assignTaxonomyOwners needs an owning deck for bookkeeping; any deck
    // referencing this species works equally well here since taxonomy
    // ownership only matters for the (still deck-scoped)
    // assignTaxonomyOwners dedup contract, not for how the resulting queue
    // item gets processed.
    final membershipDeckId = await _workRepository.loadAnyDeckIdForSpecies(
      speciesId,
    );
    if (membershipDeckId == null) return;
    await _workRepository.assignTaxonomyOwners(
      deckId: membershipDeckId,
      items: workPlan,
    );
  }

  Future<void> _retryOrFail(
    String speciesId,
    EnrichmentStage capability, {
    required String error,
    required EnrichmentFailureKind failureKind,
  }) async {
    final gaveUp = await _workRepository.recordCapabilityAttemptFailure(
      speciesId,
      capability,
      maxAttempts: failureKind == EnrichmentFailureKind.permanent
          ? 1
          : _maxAttempts,
      backoffSteps: _retryBackoffSteps,
      error: error,
      failureKind: failureKind.name,
    );
    await _diagnostics.recordEvent(
      category: 'enrichment',
      eventType: gaveUp
          ? 'capability_failed_permanent'
          : 'capability_retry_scheduled',
      subjectType: 'species',
      subjectId: speciesId,
      level: 'warning',
      message: error,
      details: {'capability': capability.name, 'failureKind': failureKind.name},
    );
    if (gaveUp) {
      _log.warn('Giving up on ${capability.name} for $speciesId '
          '(${failureKind.name})');
    }
  }

  Future<void> _retryOrFailTaxonomy(
    String workKey, {
    required String error,
    required EnrichmentFailureKind failureKind,
  }) async {
    final gaveUp = await _workRepository.recordTaxonomyCapabilityAttemptFailure(
      workKey,
      maxAttempts: failureKind == EnrichmentFailureKind.permanent
          ? 1
          : _maxAttempts,
      backoffSteps: _retryBackoffSteps,
      error: error,
      failureKind: failureKind.name,
    );
    await _diagnostics.recordEvent(
      category: 'enrichment',
      eventType: gaveUp
          ? 'capability_failed_permanent'
          : 'capability_retry_scheduled',
      subjectType: 'taxonomy',
      subjectId: workKey,
      level: 'warning',
      message: error,
      details: {
        'capability': 'taxonomyCommonNames',
        'failureKind': failureKind.name,
      },
    );
    if (gaveUp) {
      _log.warn(
        'Giving up on taxonomy common names for $workKey '
        '(${failureKind.name})',
      );
    }
  }
}
