import 'package:discere/enrichment/repository/enrichment_job_repository.dart';

/// User-facing state for the per-deck enrichment hint.
///
/// Distilled from the 9 internal [EnrichmentJobStatus] values plus modifiers
/// (host cooldown, retry waits, transient permanent failures) into a flat list
/// of 9 mutually exclusive states the UI can switch on.
enum DeckEnrichmentState {
  /// No enrichment is active or pending and nothing has ever been attempted.
  /// The UI shows nothing.
  hidden,

  /// Job is queued and has never been attempted.
  pending,

  /// Image-loading stages (`base`, `inatPrimary`) are still in flight.
  /// At least one species does not yet have an image or no-result marker.
  /// The deck is not yet learnable.
  loadingBase,

  /// Both `base` and `inatPrimary` reached terminal state for all species.
  /// The deck is learnable, but `names` and/or `inatBackfill` are still
  /// running. The UI uses the same color as [done] to signal learnability.
  loadingExtended,

  /// Enrichment completed successfully and no species permanently failed.
  done,

  /// Enrichment completed but some species permanently failed and have
  /// neither image nor common names. The deck is learnable.
  doneWithGaps,

  /// Active or pending work, but the host cooldown has been in effect for
  /// longer than the display threshold. Overrides [loadingBase] and
  /// [loadingExtended] so the user sees what is blocking progress.
  cooldown,

  /// Job is in [EnrichmentJobStatus.retryScheduled] and the next attempt is
  /// further in the future than the pause display threshold. Overrides
  /// [loadingBase] and [loadingExtended].
  paused,

  /// The whole job failed permanently. Deck is not learnable; user must
  /// re-trigger the enrichment from the Edit-Deck page.
  failed,
}

/// Compute the user-facing [DeckEnrichmentState] from the job record and the
/// service-level modifiers.
///
/// Pure function, no IO. Caller injects [now] for testing.
DeckEnrichmentState computeDeckEnrichmentState({
  required EnrichmentJobRecord job,
  required bool hasActiveHostCooldown,
  required DateTime? cooldownActiveSince,
  required bool hasTransientPermanentFailure,
  DateTime? now,
  Duration cooldownDisplayThreshold = const Duration(seconds: 30),
  Duration pauseDisplayThreshold = const Duration(minutes: 2),
}) {
  final timestamp = now ?? DateTime.now();

  switch (job.status) {
    case EnrichmentJobStatus.cancelled:
      return DeckEnrichmentState.hidden;
    case EnrichmentJobStatus.completed:
      return hasTransientPermanentFailure
          ? DeckEnrichmentState.doneWithGaps
          : DeckEnrichmentState.done;
    case EnrichmentJobStatus.failedPermanent:
      return DeckEnrichmentState.failed;
    case EnrichmentJobStatus.queued:
    case EnrichmentJobStatus.runningForeground:
    case EnrichmentJobStatus.runningBackground:
    case EnrichmentJobStatus.pausedBySystem:
    case EnrichmentJobStatus.retryScheduled:
    case EnrichmentJobStatus.failedTemporary:
      break;
  }

  // Modifiers override loading states.
  if (hasActiveHostCooldown &&
      cooldownActiveSince != null &&
      timestamp.difference(cooldownActiveSince) > cooldownDisplayThreshold) {
    return DeckEnrichmentState.cooldown;
  }

  final nextAttemptAt = job.nextAttemptAt;
  if (job.status == EnrichmentJobStatus.retryScheduled &&
      nextAttemptAt != null &&
      nextAttemptAt.difference(timestamp) > pauseDisplayThreshold) {
    return DeckEnrichmentState.paused;
  }

  if (job.everySpeciesHasImage) {
    return DeckEnrichmentState.loadingExtended;
  }

  if (job.status == EnrichmentJobStatus.queued && job.attemptedAt == null) {
    return DeckEnrichmentState.pending;
  }

  return DeckEnrichmentState.loadingBase;
}
