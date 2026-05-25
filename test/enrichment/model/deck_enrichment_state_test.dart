import 'package:discere/enrichment/model/deck_enrichment_state.dart';
import 'package:discere/enrichment/repository/enrichment_job_repository.dart';
import 'package:flutter_test/flutter_test.dart';

EnrichmentJobRecord _record({
  EnrichmentJobStatus status = EnrichmentJobStatus.queued,
  EnrichmentJobPayload payload = const EnrichmentJobPayload(speciesIds: ['s1']),
  Map<EnrichmentStage, EnrichmentStageState>? stageStates,
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
    payload: payload,
    failureKind: null,
    lastError: null,
    progressCompleted: 0,
    progressTotal: 0,
    retryCount: 0,
    nextAttemptAt: nextAttemptAt,
    leaseOwner: null,
    leaseExpiresAt: null,
    updatedAt: DateTime(2026, 1, 1),
    stageStates:
        stageStates ??
        const {
          EnrichmentStage.cover: EnrichmentStageState.skipped,
          EnrichmentStage.nameResolution: EnrichmentStageState.skipped,
          EnrichmentStage.base: EnrichmentStageState.pending,
          EnrichmentStage.inatPrimary: EnrichmentStageState.pending,
          EnrichmentStage.names: EnrichmentStageState.pending,
          EnrichmentStage.inatBackfill: EnrichmentStageState.pending,
        },
  );
}

Map<EnrichmentStage, EnrichmentStageState> _allSucceededExceptExtended() => {
  EnrichmentStage.cover: EnrichmentStageState.succeeded,
  EnrichmentStage.nameResolution: EnrichmentStageState.skipped,
  EnrichmentStage.base: EnrichmentStageState.succeeded,
  EnrichmentStage.inatPrimary: EnrichmentStageState.succeeded,
  EnrichmentStage.names: EnrichmentStageState.pending,
  EnrichmentStage.inatBackfill: EnrichmentStageState.pending,
};

void main() {
  final now = DateTime(2026, 5, 25, 12, 0, 0);

  group('computeDeckEnrichmentState', () {
    test('cancelled → hidden', () {
      expect(
        computeDeckEnrichmentState(
          job: _record(status: EnrichmentJobStatus.cancelled),
          hasActiveHostCooldown: false,
          cooldownActiveSince: null,
          hasTransientPermanentFailure: false,
          now: now,
        ),
        DeckEnrichmentState.hidden,
      );
    });

    test('queued + never attempted → pending', () {
      expect(
        computeDeckEnrichmentState(
          job: _record(status: EnrichmentJobStatus.queued, attemptedAt: null),
          hasActiveHostCooldown: false,
          cooldownActiveSince: null,
          hasTransientPermanentFailure: false,
          now: now,
        ),
        DeckEnrichmentState.pending,
      );
    });

    test('running, base not done → loadingBase', () {
      expect(
        computeDeckEnrichmentState(
          job: _record(
            status: EnrichmentJobStatus.runningForeground,
            attemptedAt: now,
          ),
          hasActiveHostCooldown: false,
          cooldownActiveSince: null,
          hasTransientPermanentFailure: false,
          now: now,
        ),
        DeckEnrichmentState.loadingBase,
      );
    });

    test('running, every species has image → loadingExtended', () {
      expect(
        computeDeckEnrichmentState(
          job: _record(
            status: EnrichmentJobStatus.runningForeground,
            stageStates: _allSucceededExceptExtended(),
            attemptedAt: now,
          ),
          hasActiveHostCooldown: false,
          cooldownActiveSince: null,
          hasTransientPermanentFailure: false,
          now: now,
        ),
        DeckEnrichmentState.loadingExtended,
      );
    });

    test('completed → done', () {
      expect(
        computeDeckEnrichmentState(
          job: _record(status: EnrichmentJobStatus.completed),
          hasActiveHostCooldown: false,
          cooldownActiveSince: null,
          hasTransientPermanentFailure: false,
          now: now,
        ),
        DeckEnrichmentState.done,
      );
    });

    test('completed + transient permanent failure → doneWithGaps', () {
      expect(
        computeDeckEnrichmentState(
          job: _record(status: EnrichmentJobStatus.completed),
          hasActiveHostCooldown: false,
          cooldownActiveSince: null,
          hasTransientPermanentFailure: true,
          now: now,
        ),
        DeckEnrichmentState.doneWithGaps,
      );
    });

    test('failedPermanent → failed', () {
      expect(
        computeDeckEnrichmentState(
          job: _record(status: EnrichmentJobStatus.failedPermanent),
          hasActiveHostCooldown: false,
          cooldownActiveSince: null,
          hasTransientPermanentFailure: false,
          now: now,
        ),
        DeckEnrichmentState.failed,
      );
    });

    test('cooldown briefer than threshold → loadingBase (no surfacing)', () {
      expect(
        computeDeckEnrichmentState(
          job: _record(
            status: EnrichmentJobStatus.runningForeground,
            attemptedAt: now,
          ),
          hasActiveHostCooldown: true,
          cooldownActiveSince: now.subtract(const Duration(seconds: 10)),
          hasTransientPermanentFailure: false,
          now: now,
        ),
        DeckEnrichmentState.loadingBase,
      );
    });

    test('cooldown longer than threshold → cooldown', () {
      expect(
        computeDeckEnrichmentState(
          job: _record(
            status: EnrichmentJobStatus.runningForeground,
            attemptedAt: now,
          ),
          hasActiveHostCooldown: true,
          cooldownActiveSince: now.subtract(const Duration(seconds: 45)),
          hasTransientPermanentFailure: false,
          now: now,
        ),
        DeckEnrichmentState.cooldown,
      );
    });

    test('retryScheduled with nextAttemptAt < 2min → loadingBase', () {
      expect(
        computeDeckEnrichmentState(
          job: _record(
            status: EnrichmentJobStatus.retryScheduled,
            attemptedAt: now,
            nextAttemptAt: now.add(const Duration(seconds: 90)),
          ),
          hasActiveHostCooldown: false,
          cooldownActiveSince: null,
          hasTransientPermanentFailure: false,
          now: now,
        ),
        DeckEnrichmentState.loadingBase,
      );
    });

    test('retryScheduled with nextAttemptAt > 2min → paused', () {
      expect(
        computeDeckEnrichmentState(
          job: _record(
            status: EnrichmentJobStatus.retryScheduled,
            attemptedAt: now,
            nextAttemptAt: now.add(const Duration(minutes: 10)),
          ),
          hasActiveHostCooldown: false,
          cooldownActiveSince: null,
          hasTransientPermanentFailure: false,
          now: now,
        ),
        DeckEnrichmentState.paused,
      );
    });

    test('cooldown wins over paused when both apply', () {
      expect(
        computeDeckEnrichmentState(
          job: _record(
            status: EnrichmentJobStatus.retryScheduled,
            attemptedAt: now,
            nextAttemptAt: now.add(const Duration(minutes: 10)),
          ),
          hasActiveHostCooldown: true,
          cooldownActiveSince: now.subtract(const Duration(seconds: 45)),
          hasTransientPermanentFailure: false,
          now: now,
        ),
        DeckEnrichmentState.cooldown,
      );
    });

    test('done overrides cooldown (terminal state always wins)', () {
      expect(
        computeDeckEnrichmentState(
          job: _record(status: EnrichmentJobStatus.completed),
          hasActiveHostCooldown: true,
          cooldownActiveSince: now.subtract(const Duration(minutes: 5)),
          hasTransientPermanentFailure: false,
          now: now,
        ),
        DeckEnrichmentState.done,
      );
    });
  });
}
