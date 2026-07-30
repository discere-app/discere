import 'package:discere/enrichment/queue/model/deck_enrichment_projection.dart';
import 'package:discere/enrichment/queue/repository/enrichment_job_repository.dart';

/// User-facing state for the per-deck enrichment hint.
///
/// Distilled from the deck's cover job status plus its species/taxonomy
/// [DeckEnrichmentProjection] (host cooldown, retry waits, permanent
/// failures) into a flat list of mutually exclusive states the UI can switch
/// on.
enum DeckEnrichmentState {
  /// No enrichment is active or pending and nothing has ever been attempted.
  /// The UI shows nothing.
  hidden,

  /// Scheduled but nothing has started running yet.
  pending,

  /// Image-loading capabilities (`base`, `inatPrimary`) are still in flight
  /// for at least one species. The deck is not yet learnable.
  loadingBase,

  /// Every species has reached a terminal image outcome, but common names
  /// and/or taxonomy/backfill work is still running (or the deck's cover job
  /// hasn't finished yet). The UI uses the same color as [done] to signal
  /// learnability.
  loadingExtended,

  /// All species/taxonomy work (and the cover job, if any) reached terminal
  /// state and no capability permanently failed.
  done,

  /// All work reached terminal state, but some non-image capability
  /// (common names, taxonomy, backfill, or an unresolved name) permanently
  /// failed. The deck is still fully learnable.
  doneWithGaps,

  /// Active or pending work, but the host cooldown has been in effect for
  /// longer than the display threshold. Overrides [loadingBase] and
  /// [loadingExtended] so the user sees what is blocking progress.
  cooldown,

  /// The soonest retry across the deck's cover job and species/taxonomy work
  /// is further in the future than the pause display threshold. Overrides
  /// [loadingBase] and [loadingExtended].
  paused,

  /// Every species' image capabilities are terminal, no image was ever
  /// obtained for any of them, and at least one image capability
  /// (`base`/`inatPrimary`) permanently failed. Deck is not learnable; user
  /// must re-trigger enrichment from the Edit-Deck page.
  failed,
}

/// Compute the user-facing [DeckEnrichmentState] from the deck's cover job
/// (if any), its species/taxonomy work projection, and the service-level
/// modifiers.
///
/// Pure function, no IO. Caller injects [now] for testing.
DeckEnrichmentState computeDeckEnrichmentState({
  required EnrichmentJobRecord? coverJob,
  required DeckEnrichmentProjection projection,
  required bool hasActiveHostCooldown,
  required DateTime? cooldownActiveSince,
  DateTime? now,
  Duration cooldownDisplayThreshold = const Duration(seconds: 30),
  Duration pauseDisplayThreshold = const Duration(minutes: 2),
}) {
  final timestamp = now ?? DateTime.now();

  if (coverJob?.status == EnrichmentJobStatus.cancelled) {
    return DeckEnrichmentState.hidden;
  }
  final hasAnyWorkKnown = coverJob != null || projection.speciesCount > 0;
  if (!hasAnyWorkKnown) {
    return DeckEnrichmentState.hidden;
  }

  // Terminal outcomes always win, regardless of any modifier below — an
  // already-finished (or permanently-failed) deck never needs to show a
  // cooldown/pause hint, matching the old per-job-status switch that
  // returned immediately for `completed`/`failedPermanent` before ever
  // consulting the cooldown/retry modifiers.
  if (projection.imageStagesComplete &&
      !projection.hasAnyImage &&
      projection.anyImagePermanentFailure) {
    return DeckEnrichmentState.failed;
  }

  final coverTerminal =
      coverJob == null ||
      coverJob.status == EnrichmentJobStatus.completed ||
      coverJob.status == EnrichmentJobStatus.failedPermanent;

  if (projection.imageStagesComplete &&
      coverTerminal &&
      projection.allSpeciesWorkTerminal) {
    return projection.anyPermanentFailure
        ? DeckEnrichmentState.doneWithGaps
        : DeckEnrichmentState.done;
  }

  // Modifiers override the remaining (non-terminal) loading states.
  if (hasActiveHostCooldown &&
      cooldownActiveSince != null &&
      timestamp.difference(cooldownActiveSince) > cooldownDisplayThreshold) {
    return DeckEnrichmentState.cooldown;
  }

  final earliestRetryAt = earliestDeckRetryAt(coverJob, projection);
  if (earliestRetryAt != null &&
      earliestRetryAt.difference(timestamp) > pauseDisplayThreshold) {
    return DeckEnrichmentState.paused;
  }

  if (projection.imageStagesComplete) {
    return DeckEnrichmentState.loadingExtended;
  }

  final neverAttempted =
      coverJob == null ||
      (coverJob.status == EnrichmentJobStatus.queued &&
          coverJob.attemptedAt == null);
  if (projection.speciesCount == 0 && neverAttempted) {
    return DeckEnrichmentState.pending;
  }

  return DeckEnrichmentState.loadingBase;
}

/// The soonest retry moment across the deck's cover job (if it is itself
/// waiting on a retry) and its species/taxonomy/unresolved-name work. Public
/// so the queue service can reuse it for its per-deck pause-display timers,
/// which need the exact same combined value [computeDeckEnrichmentState]
/// uses to decide when to switch into [DeckEnrichmentState.paused].
DateTime? earliestDeckRetryAt(
  EnrichmentJobRecord? coverJob,
  DeckEnrichmentProjection projection,
) {
  var earliest = projection.earliestRetryAt;
  if (coverJob?.status == EnrichmentJobStatus.retryScheduled) {
    final coverNextAttempt = coverJob!.nextAttemptAt;
    if (coverNextAttempt != null &&
        (earliest == null || coverNextAttempt.isBefore(earliest))) {
      earliest = coverNextAttempt;
    }
  }
  return earliest;
}
