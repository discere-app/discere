import 'package:discere/enrichment/queue/model/deck_enrichment_projection.dart';
import 'package:discere/enrichment/queue/model/deck_enrichment_state.dart';
import 'package:discere/enrichment/queue/repository/enrichment_job_repository.dart';
import 'package:flutter_test/flutter_test.dart';

EnrichmentJobRecord _coverJob({
  EnrichmentJobStatus status = EnrichmentJobStatus.completed,
  DateTime? attemptedAt,
  DateTime? completedAt,
  DateTime? nextAttemptAt,
}) {
  return EnrichmentJobRecord(
    deckId: 'deck-1',
    status: status,
    attemptedAt: attemptedAt,
    completedAt: completedAt,
    currentStage: null,
    payload: const EnrichmentJobPayload(),
    failureKind: null,
    lastError: null,
    progressCompleted: 0,
    progressTotal: 0,
    retryCount: 0,
    nextAttemptAt: nextAttemptAt,
    leaseOwner: null,
    leaseExpiresAt: null,
    updatedAt: DateTime(2026, 1, 1),
    stageStates: const {EnrichmentStage.cover: EnrichmentStageState.skipped},
  );
}

DeckEnrichmentProjection _projection({
  int speciesCount = 1,
  int imageCompleteSpeciesCount = 0,
  int imageDoneSpeciesCount = 0,
  int speciesCommonNamesWantedCount = 0,
  int speciesCommonNamesTerminalCount = 0,
  int inatBackfillWantedCount = 0,
  int inatBackfillTerminalCount = 0,
  int taxonomyTotalCount = 0,
  int taxonomyTerminalCount = 0,
  int pendingUnresolvedNameCount = 0,
  bool anyPermanentFailure = false,
  bool anyImagePermanentFailure = false,
  bool hasImmediatePendingWork = false,
  DateTime? earliestRetryAt,
}) {
  return DeckEnrichmentProjection(
    deckId: 'deck-1',
    speciesCount: speciesCount,
    imageCompleteSpeciesCount: imageCompleteSpeciesCount,
    imageDoneSpeciesCount: imageDoneSpeciesCount,
    speciesCommonNamesWantedCount: speciesCommonNamesWantedCount,
    speciesCommonNamesTerminalCount: speciesCommonNamesTerminalCount,
    inatBackfillWantedCount: inatBackfillWantedCount,
    inatBackfillTerminalCount: inatBackfillTerminalCount,
    taxonomyTotalCount: taxonomyTotalCount,
    taxonomyTerminalCount: taxonomyTerminalCount,
    pendingUnresolvedNameCount: pendingUnresolvedNameCount,
    wantsInatPhotosSpeciesCount: 0,
    wantsCommonNamesSpeciesCount: 0,
    anyPermanentFailure: anyPermanentFailure,
    anyImagePermanentFailure: anyImagePermanentFailure,
    hasImmediatePendingWork: hasImmediatePendingWork,
    earliestRetryAt: earliestRetryAt,
  );
}

/// A fully-done projection: every species has an image and every other
/// capability wanted for the deck has also reached a terminal state.
DeckEnrichmentProjection _allDoneProjection({
  bool anyPermanentFailure = false,
}) {
  return _projection(
    speciesCount: 1,
    imageCompleteSpeciesCount: 1,
    imageDoneSpeciesCount: 1,
    speciesCommonNamesWantedCount: 1,
    speciesCommonNamesTerminalCount: 1,
    inatBackfillWantedCount: 1,
    inatBackfillTerminalCount: 1,
    taxonomyTotalCount: 1,
    taxonomyTerminalCount: 1,
    anyPermanentFailure: anyPermanentFailure,
  );
}

void main() {
  final now = DateTime(2026, 5, 25, 12, 0, 0);

  group('computeDeckEnrichmentState', () {
    test('cover job cancelled → hidden', () {
      expect(
        computeDeckEnrichmentState(
          coverJob: _coverJob(status: EnrichmentJobStatus.cancelled),
          projection: _projection(),
          hasActiveHostCooldown: false,
          cooldownActiveSince: null,
          now: now,
        ),
        DeckEnrichmentState.hidden,
      );
    });

    test('no cover job and no species known → hidden', () {
      expect(
        computeDeckEnrichmentState(
          coverJob: null,
          projection: _projection(speciesCount: 0),
          hasActiveHostCooldown: false,
          cooldownActiveSince: null,
          now: now,
        ),
        DeckEnrichmentState.hidden,
      );
    });

    test('queued + never attempted, no species yet → pending', () {
      expect(
        computeDeckEnrichmentState(
          coverJob: _coverJob(
            status: EnrichmentJobStatus.queued,
            attemptedAt: null,
          ),
          projection: _projection(speciesCount: 0),
          hasActiveHostCooldown: false,
          cooldownActiveSince: null,
          now: now,
        ),
        DeckEnrichmentState.pending,
      );
    });

    test('base not done for some species → loadingBase', () {
      expect(
        computeDeckEnrichmentState(
          coverJob: _coverJob(
            status: EnrichmentJobStatus.runningForeground,
            attemptedAt: now,
          ),
          projection: _projection(
            speciesCount: 2,
            imageCompleteSpeciesCount: 1,
          ),
          hasActiveHostCooldown: false,
          cooldownActiveSince: null,
          now: now,
        ),
        DeckEnrichmentState.loadingBase,
      );
    });

    test('every species image-complete but common names still pending → '
        'loadingExtended', () {
      expect(
        computeDeckEnrichmentState(
          coverJob: _coverJob(status: EnrichmentJobStatus.completed),
          projection: _projection(
            speciesCount: 1,
            imageCompleteSpeciesCount: 1,
            imageDoneSpeciesCount: 1,
            speciesCommonNamesWantedCount: 1,
            speciesCommonNamesTerminalCount: 0,
          ),
          hasActiveHostCooldown: false,
          cooldownActiveSince: null,
          now: now,
        ),
        DeckEnrichmentState.loadingExtended,
      );
    });

    test('everything terminal, no failures → done', () {
      expect(
        computeDeckEnrichmentState(
          coverJob: _coverJob(status: EnrichmentJobStatus.completed),
          projection: _allDoneProjection(),
          hasActiveHostCooldown: false,
          cooldownActiveSince: null,
          now: now,
        ),
        DeckEnrichmentState.done,
      );
    });

    test('everything terminal, a non-image capability permanently failed → '
        'doneWithGaps', () {
      expect(
        computeDeckEnrichmentState(
          coverJob: _coverJob(status: EnrichmentJobStatus.completed),
          projection: _allDoneProjection(anyPermanentFailure: true),
          hasActiveHostCooldown: false,
          cooldownActiveSince: null,
          now: now,
        ),
        DeckEnrichmentState.doneWithGaps,
      );
    });

    test('image stages terminal, no image ever obtained, image capability '
        'permanently failed → failed', () {
      expect(
        computeDeckEnrichmentState(
          coverJob: _coverJob(status: EnrichmentJobStatus.completed),
          projection: _projection(
            speciesCount: 1,
            imageCompleteSpeciesCount: 1,
            imageDoneSpeciesCount: 0,
            anyImagePermanentFailure: true,
            anyPermanentFailure: true,
          ),
          hasActiveHostCooldown: false,
          cooldownActiveSince: null,
          now: now,
        ),
        DeckEnrichmentState.failed,
      );
    });

    test('common-names-only permanent failure does not surface as failed '
        '(deck still has an image)', () {
      expect(
        computeDeckEnrichmentState(
          coverJob: _coverJob(status: EnrichmentJobStatus.completed),
          projection: _allDoneProjection(anyPermanentFailure: true),
          hasActiveHostCooldown: false,
          cooldownActiveSince: null,
          now: now,
        ),
        isNot(DeckEnrichmentState.failed),
      );
    });

    test('cooldown briefer than threshold → loadingBase (no surfacing)', () {
      expect(
        computeDeckEnrichmentState(
          coverJob: _coverJob(
            status: EnrichmentJobStatus.runningForeground,
            attemptedAt: now,
          ),
          projection: _projection(
            speciesCount: 2,
            imageCompleteSpeciesCount: 1,
          ),
          hasActiveHostCooldown: true,
          cooldownActiveSince: now.subtract(const Duration(seconds: 10)),
          now: now,
        ),
        DeckEnrichmentState.loadingBase,
      );
    });

    test('cooldown longer than threshold → cooldown', () {
      expect(
        computeDeckEnrichmentState(
          coverJob: _coverJob(
            status: EnrichmentJobStatus.runningForeground,
            attemptedAt: now,
          ),
          projection: _projection(
            speciesCount: 2,
            imageCompleteSpeciesCount: 1,
          ),
          hasActiveHostCooldown: true,
          cooldownActiveSince: now.subtract(const Duration(seconds: 45)),
          now: now,
        ),
        DeckEnrichmentState.cooldown,
      );
    });

    test('retryScheduled with nextAttemptAt < 2min → loadingBase', () {
      expect(
        computeDeckEnrichmentState(
          coverJob: _coverJob(status: EnrichmentJobStatus.completed),
          projection: _projection(
            speciesCount: 2,
            imageCompleteSpeciesCount: 1,
            earliestRetryAt: now.add(const Duration(seconds: 90)),
          ),
          hasActiveHostCooldown: false,
          cooldownActiveSince: null,
          now: now,
        ),
        DeckEnrichmentState.loadingBase,
      );
    });

    test('retryScheduled with nextAttemptAt > 2min → paused', () {
      expect(
        computeDeckEnrichmentState(
          coverJob: _coverJob(status: EnrichmentJobStatus.completed),
          projection: _projection(
            speciesCount: 2,
            imageCompleteSpeciesCount: 1,
            earliestRetryAt: now.add(const Duration(minutes: 10)),
          ),
          hasActiveHostCooldown: false,
          cooldownActiveSince: null,
          now: now,
        ),
        DeckEnrichmentState.paused,
      );
    });

    test('cover job itself retryScheduled far in the future → paused', () {
      expect(
        computeDeckEnrichmentState(
          coverJob: _coverJob(
            status: EnrichmentJobStatus.retryScheduled,
            attemptedAt: now,
            nextAttemptAt: now.add(const Duration(minutes: 10)),
          ),
          projection: _projection(
            speciesCount: 2,
            imageCompleteSpeciesCount: 1,
          ),
          hasActiveHostCooldown: false,
          cooldownActiveSince: null,
          now: now,
        ),
        DeckEnrichmentState.paused,
      );
    });

    test('cooldown wins over paused when both apply', () {
      expect(
        computeDeckEnrichmentState(
          coverJob: _coverJob(status: EnrichmentJobStatus.completed),
          projection: _projection(
            speciesCount: 2,
            imageCompleteSpeciesCount: 1,
            earliestRetryAt: now.add(const Duration(minutes: 10)),
          ),
          hasActiveHostCooldown: true,
          cooldownActiveSince: now.subtract(const Duration(seconds: 45)),
          now: now,
        ),
        DeckEnrichmentState.cooldown,
      );
    });

    test('done overrides cooldown (terminal state always wins)', () {
      expect(
        computeDeckEnrichmentState(
          coverJob: _coverJob(status: EnrichmentJobStatus.completed),
          projection: _allDoneProjection(),
          hasActiveHostCooldown: true,
          cooldownActiveSince: now.subtract(const Duration(minutes: 5)),
          now: now,
        ),
        DeckEnrichmentState.done,
      );
    });

    test('failed overrides cooldown (terminal state always wins)', () {
      expect(
        computeDeckEnrichmentState(
          coverJob: _coverJob(status: EnrichmentJobStatus.completed),
          projection: _projection(
            speciesCount: 1,
            imageCompleteSpeciesCount: 1,
            imageDoneSpeciesCount: 0,
            anyImagePermanentFailure: true,
          ),
          hasActiveHostCooldown: true,
          cooldownActiveSince: now.subtract(const Duration(minutes: 5)),
          now: now,
        ),
        DeckEnrichmentState.failed,
      );
    });
  });
}
