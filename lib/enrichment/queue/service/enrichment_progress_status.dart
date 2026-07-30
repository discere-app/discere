import 'package:discere/enrichment/queue/model/deck_enrichment_projection.dart';
import 'package:discere/enrichment/queue/model/inat_enrichment_status.dart';
import 'package:discere/enrichment/queue/repository/enrichment_job_repository.dart';
export 'package:discere/enrichment/queue/model/inat_enrichment_status.dart';

/// One deck's cover job (if any) plus its species/taxonomy work snapshot —
/// the unit [deriveEnrichmentStatus] aggregates across every known deck.
/// There is no single per-deck "job status" anymore once species/taxonomy
/// work is reactive rather than one sequential stage ladder, so status
/// derivation works off this pair directly instead of `EnrichmentJobRecord`
/// alone.
class DeckWorkSnapshot {
  final String deckId;
  final EnrichmentJobRecord? coverJob;
  final DeckEnrichmentProjection projection;

  const DeckWorkSnapshot({
    required this.deckId,
    required this.coverJob,
    required this.projection,
  });

  bool get hasPendingWork =>
      (coverJob?.hasPendingWork ?? false) || !projection.allSpeciesWorkTerminal;

  /// Actively being worked on imminently, as opposed to merely queued for a
  /// later retry (host cooldown, escalating backoff).
  bool get hasImmediatePendingWork =>
      (coverJob != null &&
          (coverJob!.status == EnrichmentJobStatus.queued ||
              coverJob!.status == EnrichmentJobStatus.runningForeground ||
              coverJob!.status == EnrichmentJobStatus.runningBackground ||
              coverJob!.status == EnrichmentJobStatus.pausedBySystem)) ||
      projection.hasImmediatePendingWork;
}

/// Progress across every capability this deck has (image, common names,
/// backfill, taxonomy, cover) — replaces the old single-active-stage
/// progress display, since multiple capabilities now progress concurrently
/// for the same deck rather than one at a time.
({int completed, int total}) deriveDisplayedProgress(DeckWorkSnapshot deck) {
  final projection = deck.projection;
  var completed =
      projection.imageCompleteSpeciesCount +
      projection.speciesCommonNamesTerminalCount +
      projection.inatBackfillTerminalCount +
      projection.taxonomyTerminalCount;
  var total =
      projection.speciesCount +
      projection.speciesCommonNamesWantedCount +
      projection.inatBackfillWantedCount +
      projection.taxonomyTotalCount;

  final coverJob = deck.coverJob;
  final coverWanted =
      coverJob?.payload.coverImageUrl?.trim().isNotEmpty ?? false;
  if (coverWanted) {
    total += 1;
    if (coverJob!.status == EnrichmentJobStatus.completed) {
      completed += 1;
    }
  }
  return (completed: completed, total: total);
}

bool isReadyForDeck(DeckEnrichmentProjection projection) =>
    projection.hasAnyImage;

/// Aggregates every known deck's [DeckWorkSnapshot] into one global status
/// for the app-wide enrichment banner.
INatEnrichmentStatus deriveEnrichmentStatus(
  List<DeckWorkSnapshot> decks, {
  bool hasActiveHostCooldown = false,
  bool preferBackgroundMessaging = false,
}) {
  final pendingDecks = decks.where((deck) => deck.hasPendingWork).toList();
  if (pendingDecks.isEmpty) return INatEnrichmentStatus.idle;

  final readyDeckCount = pendingDecks
      .where((deck) => deck.projection.hasAnyImage)
      .length;
  final immediatePendingDecks = pendingDecks
      .where((deck) => deck.hasImmediatePendingWork)
      .toList();

  var completed = 0;
  var total = 0;
  var hasBasePending = false;
  var hasInatPending = false;
  var hasCoverPending = false;
  for (final deck in pendingDecks) {
    final progress = deriveDisplayedProgress(deck);
    completed += progress.completed;
    total += progress.total;
    if (!deck.projection.imageStagesComplete) {
      hasBasePending = true;
    } else if (!deck.projection.allSpeciesWorkTerminal) {
      hasInatPending = true;
    }
    if (deck.coverJob?.hasPendingWork ?? false) {
      hasCoverPending = true;
    }
  }

  final phase = hasBasePending
      ? INatEnrichmentPhase.base
      : hasInatPending
      ? INatEnrichmentPhase.inat
      : hasCoverPending
      ? INatEnrichmentPhase.cover
      : INatEnrichmentPhase.idle;

  return INatEnrichmentStatus(
    isRunning: immediatePendingDecks.isNotEmpty,
    hasPendingWork: true,
    hasActiveWork: immediatePendingDecks.isNotEmpty,
    hasActiveHostCooldown: hasActiveHostCooldown,
    preferBackgroundMessaging: preferBackgroundMessaging,
    phase: phase,
    completed: completed,
    total: total,
    activeDeckCount: pendingDecks.length,
    readyDeckCount: readyDeckCount,
    totalDeckCount: decks.length,
  );
}
