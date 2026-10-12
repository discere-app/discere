import 'package:discere/enrichment/model/enrichment_capability.dart';
import 'package:discere/enrichment/model/enrichment_work_state.dart';
import 'package:discere/enrichment/pipeline/model/inat_work_item.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_ownership_repository.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_claim_repository.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_outcome_repository.dart';
import 'package:discere/enrichment/pipeline/repository/inat_photo_cache_repository.dart';
import 'package:discere/enrichment/pipeline/service/inat_photo_enrichment_service.dart';
import 'package:discere/enrichment/pipeline/service/species_common_name_enrichment_service.dart';
import 'package:discere/enrichment/pipeline/service/taxonomy_common_name_enrichment_service.dart';
import 'package:discere/enrichment/ports/enrichment_job_ports.dart';
import 'package:discere/enrichment/service/deck_membership_lock.dart';
import 'package:discere/enrichment/service/enrichment_failure_classifier.dart';
import 'package:discere/shared/persistence/closed_database_tolerance.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:flutter/foundation.dart';

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
  final EnrichmentOwnershipRepository _ownershipRepository;
  final INatPhotoCacheRepository _photoCacheRepository;
  final ScientificNameResolutionPort? _nameResolutionPort;
  final DeckSpeciesMutationPort? _deckSpeciesMutationPort;
  final UnresolvedNamesObserverPort? _unresolvedNamesObserver;
  final DeckMembershipLock _deckMembershipLock;

  const INatWorker(
    this._photoEnrichmentService,
    this._commonNameEnrichmentService,
    this._taxonomyEnrichmentService,
    this._claimRepository,
    this._outcomeRepository,
    this._ownershipRepository,
    this._photoCacheRepository, {
    required DeckMembershipLock deckMembershipLock,
    ScientificNameResolutionPort? nameResolutionPort,
    DeckSpeciesMutationPort? deckSpeciesMutationPort,
    UnresolvedNamesObserverPort? unresolvedNamesObserver,
  }) : _deckMembershipLock = deckMembershipLock,
       _nameResolutionPort = nameResolutionPort,
       _deckSpeciesMutationPort = deckSpeciesMutationPort,
       _unresolvedNamesObserver = unresolvedNamesObserver;

  /// Repeatedly claims and processes single work items — spaced by
  /// [_requestSpacing] — until either the queue is drained or [shouldStop]
  /// returns true. Returns whether any work was actually processed. A user
  /// database closed underneath the loop ends it early. Any other database
  /// error propagates from claiming; one raised while processing an item is
  /// booked as that item's failed attempt (see [_attempt]).
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
    await runToleratingClosedDatabase(_log, () async {
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
    });
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

  /// Runs one item's [attempt]. A failure is logged as [failure] and booked
  /// through [recordFailure] as a failed attempt of that item — a real
  /// database error included: it stays this item's failure, so an item that
  /// keeps failing burns its own retries instead of being claimed first
  /// again and stopping the queue behind it on every pass. A closed
  /// database is no item's failure, and nothing could book it: it ends the
  /// loop in [runUntilIdle] instead.
  Future<void> _attempt(
    String failure,
    Future<void> Function() attempt, {
    required Future<void> Function(Object error) recordFailure,
  }) async {
    try {
      await attempt();
    } catch (error, stackTrace) {
      if (isClosedDatabaseError(error)) rethrow;
      _log.warn(failure, error: error, stackTrace: stackTrace);
      await recordFailure(error);
    }
  }

  Future<void> _processPrimaryPhoto(String speciesId) => _attempt(
    'iNat primary photo fetch failed for $speciesId',
    () async {
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
      await _outcomeRepository.seedCapability(
        speciesId,
        EnrichmentCapability.inatBackfill,
        priorityTier: _inatBackfillPriorityTier,
      );
      await _seedTaxonomyWorkForSpecies(speciesId);
    },
    recordFailure: (error) =>
        _retryOrFailWith(speciesId, EnrichmentCapability.inatPrimary, error),
  );

  Future<void> _processBackfillPhoto(String speciesId) => _attempt(
    'iNat backfill fetch failed for $speciesId',
    () async {
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
    },
    recordFailure: (error) =>
        _retryOrFailWith(speciesId, EnrichmentCapability.inatBackfill, error),
  );

  Future<void> _processSpeciesCommonNames(String speciesId) => _attempt(
    'iNat common-name fetch failed for $speciesId',
    () async {
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
    },
    recordFailure: (error) => _retryOrFailWith(
      speciesId,
      EnrichmentCapability.speciesCommonNames,
      error,
    ),
  );

  Future<void> _processTaxonomyCommonNames(INatWorkItem item) {
    final workKey = item.taxonomyWorkKey!;
    final runtimeEntityKey = item.taxonomyRuntimeEntityKey!;
    final speciesIds = item.taxonomySpeciesIds!;
    return _attempt(
      'iNat taxonomy common-name fetch failed for $workKey',
      () async {
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
      },
      recordFailure: (error) => _retryOrFailTaxonomy(
        workKey,
        error: error.toString(),
        failureKind: classifyEnrichmentFailure(error),
      ),
    );
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
    await _attempt(
      'iNat name resolution failed for "$name"',
      () async {
        final resolved = await nameResolutionPort.resolveNames([name]);
        final speciesId = resolved[name];
        if (speciesId == null) {
          final gaveUp = await _outcomeRepository
              .recordUnresolvedNameAttemptFailure(
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
        await registerResolvedName(deckId, name, speciesId);
      },
      recordFailure: (error) =>
          _outcomeRepository.recordUnresolvedNameAttemptFailure(
            deckId,
            name,
            maxAttempts: _maxAttempts,
            backoffSteps: _retryBackoffSteps,
            error: error.toString(),
          ),
    );
  }

  /// The "straggler round" for a name resolved to [speciesId]: adds the
  /// species to [deckId], registers just this one species with the consent
  /// the name's row carries now — additive, so it merges into whatever else
  /// already tracks this species instead of overwriting it — and then
  /// deletes the row, which the registration has to read first.
  ///
  /// Runs under the [DeckMembershipLock], so it cannot land between a
  /// scheduling call's species snapshot and the ownership write that treats
  /// that snapshot as authoritative and would drop the species again.
  @visibleForTesting
  Future<void> registerResolvedName(
    String deckId,
    String name,
    String speciesId,
  ) {
    return _deckMembershipLock.run(() async {
      await _deckSpeciesMutationPort?.addSpeciesToDeck(deckId, {speciesId});
      await _ownershipRepository.registerResolvedSpeciesForDeck(
        speciesId,
        deckId,
        resolvedName: name,
      );
      await _outcomeRepository.deleteUnresolvedName(deckId, name);
    });
  }

  Future<void> _seedTaxonomyWorkForSpecies(String speciesId) async {
    final workPlan = await _taxonomyEnrichmentService
        .buildTaxonomyWorkPlanForSpecies({speciesId});
    if (workPlan.isEmpty) return;
    // No deck to attribute: taxonomy work carries no deck association (deck
    // scoping is derived from the species junction joined against
    // deckMembership, and the claim guard skips taxa with no live membership).
    await _ownershipRepository.registerTaxonomyWork(items: workPlan);
  }

  /// [_retryOrFail] for a caught [error], classified by what kind of
  /// failure it is.
  Future<void> _retryOrFailWith(
    String speciesId,
    EnrichmentCapability capability,
    Object error,
  ) => _retryOrFail(
    speciesId,
    capability,
    error: error.toString(),
    failureKind: classifyEnrichmentFailure(error),
  );

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
