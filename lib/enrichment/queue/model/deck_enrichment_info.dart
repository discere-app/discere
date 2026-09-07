/// What the UI is told about one deck's enrichment.
///
/// Deliberately narrower than what the queue service knows: error text and
/// retry timing stay inside the service and only surface through the derived
/// [DeckEnrichmentInfo.state].
library;

import 'package:discere/enrichment/queue/model/deck_enrichment_state.dart';
import 'package:discere/enrichment/queue/model/enrichment_job.dart';

/// UI-facing snapshot of a deck's enrichment work. Deliberately limited to
/// what the deck-card hint and the edit-deck section actually render —
/// internals like error text or retry timing stay inside the service and
/// only surface through the derived [state].
class DeckEnrichmentInfo {
  final EnrichmentJobStatus status;
  final DeckEnrichmentState state;
  final DateTime? lastCompletedAt;
  final DateTime? lastAttemptedAt;

  /// Same completion event as [lastCompletedAt], but only set if it
  /// happened during the *current* app session — null again after every
  /// restart, even for a deck whose [lastCompletedAt] is a durable
  /// historical date. Used only by the deck-card "just finished" hint,
  /// which is meant to confirm a just-finished run rather than stand in as
  /// a permanent "this deck is done" badge; [lastCompletedAt] itself stays
  /// durable for surfaces like the Edit Deck page that need the real date.
  final DateTime? sessionCompletedAt;
  final bool includesINatPhotos;
  final bool includesCommonNames;
  final int progressCompleted;
  final int progressTotal;
  final bool isReady;
  final bool hasActiveHostCooldown;

  /// True once every species in the deck has reached a terminal state
  /// (downloaded image or explicit no-result marker) for both image-loading
  /// capabilities — i.e. [DeckEnrichmentProjection.imageStagesComplete].
  /// Defaults to true for the "no work known yet" fallback instance, since
  /// there is nothing to wait for in that case.
  final bool imageStagesComplete;

  /// Species whose `base` image predates the currently-installed
  /// reference-DB version — see `DeckEnrichmentProjection.staleBaseSpeciesCount`.
  final int staleBaseSpeciesCount;

  const DeckEnrichmentInfo({
    required this.status,
    this.state = DeckEnrichmentState.hidden,
    required this.lastCompletedAt,
    required this.lastAttemptedAt,
    this.sessionCompletedAt,
    this.includesINatPhotos = false,
    this.includesCommonNames = false,
    this.progressCompleted = 0,
    this.progressTotal = 0,
    this.isReady = false,
    this.hasActiveHostCooldown = false,
    this.imageStagesComplete = true,
    this.staleBaseSpeciesCount = 0,
  });

  bool get includesINatEnrichment => includesINatPhotos || includesCommonNames;

  bool get hasCompletedINatEnrichment =>
      includesINatEnrichment && lastCompletedAt != null;

  bool get isActive =>
      status == EnrichmentJobStatus.runningForeground ||
      status == EnrichmentJobStatus.runningBackground;

  bool get hasPendingWork => switch (status) {
    EnrichmentJobStatus.queued ||
    EnrichmentJobStatus.runningForeground ||
    EnrichmentJobStatus.runningBackground ||
    EnrichmentJobStatus.pausedBySystem ||
    EnrichmentJobStatus.retryScheduled ||
    EnrichmentJobStatus.failedTemporary => true,
    _ => false,
  };

  bool get hasFailedAttempt =>
      status == EnrichmentJobStatus.failedTemporary ||
      status == EnrichmentJobStatus.failedPermanent;

  @override
  bool operator ==(Object other) {
    return other is DeckEnrichmentInfo &&
        other.status == status &&
        other.state == state &&
        other.lastCompletedAt == lastCompletedAt &&
        other.lastAttemptedAt == lastAttemptedAt &&
        other.sessionCompletedAt == sessionCompletedAt &&
        other.includesINatPhotos == includesINatPhotos &&
        other.includesCommonNames == includesCommonNames &&
        other.progressCompleted == progressCompleted &&
        other.progressTotal == progressTotal &&
        other.isReady == isReady &&
        other.hasActiveHostCooldown == hasActiveHostCooldown &&
        other.imageStagesComplete == imageStagesComplete &&
        other.staleBaseSpeciesCount == staleBaseSpeciesCount;
  }

  @override
  int get hashCode => Object.hash(
    status,
    state,
    lastCompletedAt,
    lastAttemptedAt,
    sessionCompletedAt,
    includesINatPhotos,
    includesCommonNames,
    progressCompleted,
    progressTotal,
    isReady,
    hasActiveHostCooldown,
    imageStagesComplete,
    staleBaseSpeciesCount,
  );
}

/// Maps a [DeckEnrichmentState] onto the coarser [EnrichmentJobStatus]
/// vocabulary [DeckEnrichmentInfo]'s derived getters (`isActive`,
/// `hasPendingWork`, `hasFailedAttempt`) already switch on. There is no
/// longer a single per-deck job status once species/taxonomy work is
/// reactive rather than one sequential stage ladder, so this is a display
/// convenience derived entirely from [state] — not read anywhere on its own.
EnrichmentJobStatus statusForDeckEnrichmentState(DeckEnrichmentState state) {
  return switch (state) {
    DeckEnrichmentState.hidden => EnrichmentJobStatus.cancelled,
    DeckEnrichmentState.pending => EnrichmentJobStatus.queued,
    DeckEnrichmentState.loadingBase || DeckEnrichmentState.loadingExtended =>
      EnrichmentJobStatus.runningForeground,
    DeckEnrichmentState.done ||
    DeckEnrichmentState.doneWithGaps => EnrichmentJobStatus.completed,
    DeckEnrichmentState.cooldown ||
    DeckEnrichmentState.paused => EnrichmentJobStatus.retryScheduled,
    DeckEnrichmentState.failed => EnrichmentJobStatus.failedPermanent,
  };
}
