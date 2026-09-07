import 'package:discere/enrichment/model/enrichment_capability.dart';
import 'package:discere/enrichment/model/enrichment_work_state.dart';
import 'package:discere/enrichment/pipeline/model/inat_work_item.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_claim_repository.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_outcome_repository.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_repository.dart';
import 'package:discere/enrichment/pipeline/repository/inat_photo_cache_repository.dart';
import 'package:discere/enrichment/pipeline/service/inat_photo_enrichment_service.dart';
import 'package:discere/enrichment/pipeline/service/species_common_name_enrichment_service.dart';
import 'package:discere/enrichment/pipeline/service/taxonomy_common_name_enrichment_service.dart';
import 'package:discere/enrichment/ports/enrichment_job_ports.dart';
import 'package:discere/enrichment/service/enrichment_failure_classifier.dart';
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
/// tables behind [EnrichmentWorkClaimRepository]. Name resolution is folded
/// into this
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
  final EnrichmentWorkClaimRepository _claimRepository;
  final EnrichmentWorkOutcomeRepository _outcomeRepository;
  final EnrichmentWorkRepository _workRepository;
  final INatPhotoCacheRepository _photoCacheRepository;
  final ScientificNameResolutionPort? _nameResolutionPort;
  final DeckSpeciesMutationPort? _deckSpeciesMutationPort;
  final UnresolvedNamesObserverPort? _unresolvedNamesObserver;

  const INatWorker(
    this._photoEnrichmentService,
    this._commonNameEnrichmentService,
    this._taxonomyEnrichmentService,
    this._claimRepository,
    this._outcomeRepository,
    this._workRepository,
    this._photoCacheRepository, {
    ScientificNameResolutionPort? nameResolutionPort,
    DeckSpeciesMutationPort? deckSpeciesMutationPort,
    UnresolvedNamesObserverPort? unresolvedNamesObserver,
  }) : _nameResolutionPort = nameResolutionPort,
       _deckSpeciesMutationPort = deckSpeciesMutationPort,
       _unresolvedNamesObserver = unresolvedNamesObserver;

  /// Repeatedly claims and processes single work items — spaced by
  /// [_requestSpacing] — until either the queue is drained or [shouldStop]
  /// returns true. Returns whether any work was actually processed.
  ///
  /// [onProgress], if given, fires after every single item is processed —
  /// see `BaseWorker.runUntilIdle`'s doc comment for why per-item (rather
  /// than per-pass) granularity is what makes the deck-card progress move
  /// live instead of jumping only once the whole call returns.
  Future<bool> runUntilIdle({
    required bool Function() shouldStop,
    void Function()? onProgress,
  }) async {
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

        final item = await _claimRepository.claimNextINatWorkItem();
        if (item == null) break;
        processedAny = true;
        _log.debug('Claimed iNat work item: $item');
        await _process(item);
        onProgress?.call();
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
        return _processPrimaryPhoto(item.speciesId!);
      case INatWorkItemKind.speciesCommonNames:
        return _processSpeciesCommonNames(item.speciesId!);
      case INatWorkItemKind.inatBackfill:
        return _processBackfillPhoto(item.speciesId!);
      case INatWorkItemKind.taxonomyCommonNames:
        return _processTaxonomyCommonNames(item);
      case INatWorkItemKind.nameResolution:
        return _processNameResolution(item);
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
          EnrichmentCapability.inatPrimary,
          error: 'iNat primary photo fetch did not complete',
          failureKind: EnrichmentFailureKind.temporary,
        );
        return;
      }
      final cachedPhotos = await _photoCacheRepository.getCachedPhotos(
        speciesId,
      );
      final state = (cachedPhotos != null && cachedPhotos.isNotEmpty)
          ? EnrichmentWorkState.done
          : EnrichmentWorkState.noResult;
      await _outcomeRepository.markCapabilityTerminal(
        speciesId,
        EnrichmentCapability.inatPrimary,
        state,
      );
      // Whether or not a primary photo was actually found, the species now
      // has a stable resolution outcome — seed backfill (a no-op fetch for
      // species confirmed to have no photos, since INatPhotoEnrichmentService
      // itself treats that as terminal-skip) and taxonomy common names.
      await _claimRepository.seedCapability(
        speciesId,
        EnrichmentCapability.inatBackfill,
        priorityTier: _inatBackfillPriorityTier,
      );
      await _seedTaxonomyWorkForSpecies(speciesId);
    } catch (error) {
      _log.warn('iNat primary photo fetch failed for $speciesId: $error');
      await _retryOrFail(
        speciesId,
        EnrichmentCapability.inatPrimary,
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
          EnrichmentCapability.inatBackfill,
          error: 'iNat backfill fetch did not complete',
          failureKind: EnrichmentFailureKind.temporary,
        );
        return;
      }
      // Backfill never gates deck readiness (only base/inatPrimary do) and
      // is a best-effort "more photos" capability, so there's no separate
      // no-result outcome worth tracking here — always 'done' once resolved.
      await _outcomeRepository.markCapabilityTerminal(
        speciesId,
        EnrichmentCapability.inatBackfill,
        EnrichmentWorkState.done,
      );
    } catch (error) {
      _log.warn('iNat backfill fetch failed for $speciesId: $error');
      await _retryOrFail(
        speciesId,
        EnrichmentCapability.inatBackfill,
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
          EnrichmentCapability.speciesCommonNames,
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
      await _outcomeRepository.markCapabilityTerminal(
        speciesId,
        EnrichmentCapability.speciesCommonNames,
        EnrichmentWorkState.done,
      );
      await _seedTaxonomyWorkForSpecies(speciesId);
    } catch (error) {
      _log.warn('iNat common-name fetch failed for $speciesId: $error');
      await _retryOrFail(
        speciesId,
        EnrichmentCapability.speciesCommonNames,
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
      await _outcomeRepository.markTaxonomyCapabilityTerminal(
        workKey,
        EnrichmentWorkState.done,
      );
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
      await _outcomeRepository.deleteUnresolvedName(deckId, name);
      return;
    }
    try {
      final resolved = await nameResolutionPort.resolveNames([name]);
      final speciesId = resolved[name];
      if (speciesId == null) {
        final gaveUp = await _outcomeRepository.recordUnresolvedNameAttemptFailure(
          deckId,
          name,
          maxAttempts: _maxAttempts,
          backoffSteps: _retryBackoffSteps,
          error: 'iNat name resolution did not resolve "$name"',
        );
        if (gaveUp) {
          _log.warn('Giving up on iNat name resolution for "$name"');
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
      await _outcomeRepository.deleteUnresolvedName(deckId, name);
    } catch (error) {
      _log.warn('iNat name resolution failed for "$name": $error');
      await _outcomeRepository.recordUnresolvedNameAttemptFailure(
        deckId,
        name,
        maxAttempts: _maxAttempts,
        backoffSteps: _retryBackoffSteps,
        error: error.toString(),
      );
    }
  }

  Future<void> _seedTaxonomyWorkForSpecies(String speciesId) async {
    final workPlan = await _taxonomyEnrichmentService
        .buildTaxonomyWorkPlanForSpecies({speciesId});
    if (workPlan.isEmpty) return;
    // No deck to attribute: taxonomy work carries no deck association (deck
    // scoping is derived from the species junction joined against
    // deckMembership, and the claim guard skips taxa with no live membership).
    await _workRepository.registerTaxonomyWork(items: workPlan);
  }

  Future<void> _retryOrFail(
    String speciesId,
    EnrichmentCapability capability, {
    required String error,
    required EnrichmentFailureKind failureKind,
  }) async {
    final gaveUp = await _outcomeRepository.recordCapabilityAttemptFailure(
      speciesId,
      capability,
      maxAttempts: failureKind == EnrichmentFailureKind.permanent
          ? 1
          : _maxAttempts,
      backoffSteps: _retryBackoffSteps,
      error: error,
      failureKind: failureKind.name,
    );
    if (gaveUp) {
      _log.warn(
        'Giving up on ${capability.name} for $speciesId '
        '(${failureKind.name})',
      );
    }
  }

  Future<void> _retryOrFailTaxonomy(
    String workKey, {
    required String error,
    required EnrichmentFailureKind failureKind,
  }) async {
    final gaveUp = await _outcomeRepository.recordTaxonomyCapabilityAttemptFailure(
      workKey,
      maxAttempts: failureKind == EnrichmentFailureKind.permanent
          ? 1
          : _maxAttempts,
      backoffSteps: _retryBackoffSteps,
      error: error,
      failureKind: failureKind.name,
    );
    if (gaveUp) {
      _log.warn(
        'Giving up on taxonomy common names for $workKey '
        '(${failureKind.name})',
      );
    }
  }
}
