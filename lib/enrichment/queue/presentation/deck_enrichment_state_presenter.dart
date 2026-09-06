/// Derivation of the user-facing [DeckEnrichmentState] from persisted work.
///
/// Kept out of `queue/model/deck_enrichment_state.dart`, which now only
/// declares the state vocabulary: this is where the deck's cover job and its
/// species/taxonomy projection get folded into one state the UI can switch
/// on. Separate from `enrichment_status_presenter.dart` because that one
/// formats localized copy and this one derives state — the two share a
/// folder, not a concern.
library;

import 'package:discere/enrichment/model/deck_enrichment_projection.dart';
import 'package:discere/enrichment/queue/model/deck_enrichment_state.dart';
import 'package:discere/enrichment/queue/model/enrichment_job.dart';

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
