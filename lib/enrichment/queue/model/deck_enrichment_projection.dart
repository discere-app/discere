/// Aggregated view of one deck's species/taxonomy work, computed from
/// `enrichment_species_capability_state`/`enrichment_taxonomy_work` joined
/// through `enrichment_species_deck_membership` — see
/// `EnrichmentWorkRepository.loadDeckProjection`.
///
/// Replaces `EnrichmentJobRecord.stageStates`/`payload` as the input to
/// deck-facing derivations (readiness, progress, phase) once the
/// producer-consumer workers replace `EnrichmentJobExecutor`. Computed over
/// every species that references this deck via
/// `enrichment_species_deck_membership`, regardless of which deck "owns"
/// the species for cross-deck dedup purposes — fixing a latent gap in the
/// old per-job model, where a deck sharing heavily-in-progress species with
/// another deck's job could report readiness based only on the subset of
/// species it happened to own.
class DeckEnrichmentProjection {
  final String deckId;
  final int speciesCount;

  /// Number of species that have reached a terminal *image* outcome: either
  /// `base` succeeded outright (no iNat photo ever needed), or `base` ended
  /// terminal-without-an-image (`noResult`/`permanentFailure`) and
  /// `inatPrimary` — seeded reactively by `BaseWorker` in exactly that case —
  /// has also reached a terminal state. Mirrors
  /// `EnrichmentJobRecord.everySpeciesHasImage`'s intent, but correct under
  /// reactive seeding, where a species that never needed `inatPrimary` has no
  /// row for it at all.
  final int imageCompleteSpeciesCount;

  /// Number of species with an actual downloaded image (`base` or
  /// `inatPrimary` in state `done` — not merely terminal, since
  /// `noResult`/`permanentFailure` mean no image landed).
  final int imageDoneSpeciesCount;

  final int speciesCommonNamesWantedCount;
  final int speciesCommonNamesTerminalCount;
  final int inatBackfillWantedCount;
  final int inatBackfillTerminalCount;

  /// Taxonomy (genus/family/order/class) common-name work items relevant to
  /// this deck's species, per `enrichment_taxonomy_work.deck_ids_json`.
  final int taxonomyTotalCount;
  final int taxonomyTerminalCount;

  /// Unresolved scientific names for this deck still being retried (not yet
  /// resolved and not yet given up on). Zero once every name either resolved
  /// into a species or reached `permanentFailure`.
  final int pendingUnresolvedNameCount;

  /// Number of this deck's species with iNat-photo/common-name consent
  /// granted (`enrichment_species_work.wants_inat_photos`/
  /// `wants_common_names`, OR'd additively across every deck that ever
  /// requested it — see the consent model doc in the enrichment-optimization
  /// plan). A deck-level "did this deck ever ask for iNat enrichment" proxy:
  /// since consent only ever grows, a species in this deck's membership
  /// wanting iNat means either this deck or a sibling deck sharing it
  /// requested it.
  final int wantsInatPhotosSpeciesCount;
  final int wantsCommonNamesSpeciesCount;

  /// Whether any capability for any of this deck's species — or any
  /// taxonomy item relevant to it — has given up permanently.
  final bool anyPermanentFailure;

  /// Whether `base` or `inatPrimary` (the two image-producing capabilities)
  /// has given up permanently for any of this deck's species. Narrower than
  /// [anyPermanentFailure] — a common-names/taxonomy/backfill failure alone
  /// does not make a deck's images unobtainable, so it must not surface as
  /// [DeckEnrichmentState.failed] the way an image failure does.
  final bool anyImagePermanentFailure;

  /// Whether at least one relevant row is actively `pending`/`running` right
  /// now, as opposed to merely `retryScheduled` and waiting out a backoff.
  /// Distinguishes "actually being worked on imminently" from "queued for a
  /// later retry" for the aggregate status banner.
  final bool hasImmediatePendingWork;

  /// The soonest `next_attempt_at` among every `retryScheduled` capability/
  /// taxonomy/unresolved-name row relevant to this deck, or null if nothing
  /// is currently waiting on a retry. Drives the "paused" UI state — there is
  /// no single job-level retry timestamp anymore once species/taxonomy work
  /// is reactive, so the projection surfaces the earliest one instead.
  final DateTime? earliestRetryAt;

  const DeckEnrichmentProjection({
    required this.deckId,
    required this.speciesCount,
    required this.imageCompleteSpeciesCount,
    required this.imageDoneSpeciesCount,
    required this.speciesCommonNamesWantedCount,
    required this.speciesCommonNamesTerminalCount,
    required this.inatBackfillWantedCount,
    required this.inatBackfillTerminalCount,
    required this.taxonomyTotalCount,
    required this.taxonomyTerminalCount,
    required this.pendingUnresolvedNameCount,
    required this.wantsInatPhotosSpeciesCount,
    required this.wantsCommonNamesSpeciesCount,
    required this.anyPermanentFailure,
    required this.anyImagePermanentFailure,
    required this.hasImmediatePendingWork,
    required this.earliestRetryAt,
  });

  static DeckEnrichmentProjection empty(String deckId) =>
      DeckEnrichmentProjection(
        deckId: deckId,
        speciesCount: 0,
        imageCompleteSpeciesCount: 0,
        imageDoneSpeciesCount: 0,
        speciesCommonNamesWantedCount: 0,
        speciesCommonNamesTerminalCount: 0,
        inatBackfillWantedCount: 0,
        inatBackfillTerminalCount: 0,
        taxonomyTotalCount: 0,
        taxonomyTerminalCount: 0,
        pendingUnresolvedNameCount: 0,
        wantsInatPhotosSpeciesCount: 0,
        wantsCommonNamesSpeciesCount: 0,
        anyPermanentFailure: false,
        anyImagePermanentFailure: false,
        hasImmediatePendingWork: false,
        earliestRetryAt: null,
      );

  /// True once every species referencing this deck has a terminal image
  /// outcome — the deck is learnable from this point on. Mirrors
  /// `EnrichmentJobRecord.everySpeciesHasImage`.
  bool get imageStagesComplete =>
      speciesCount > 0 && imageCompleteSpeciesCount >= speciesCount;

  /// True once at least one species has an actual downloaded image — "the
  /// deck has something to show", not necessarily complete. Mirrors
  /// `EnrichmentJobPayload.hasAnyImage` / `isReadyForJob`'s intent.
  bool get hasAnyImage => imageDoneSpeciesCount > 0;

  /// True once every capability wanted for this deck's species/taxonomy —
  /// images, common names, backfill, taxonomy names, and unresolved names —
  /// has reached a terminal outcome. Does not depend on the deck's cover job,
  /// which is tracked separately.
  bool get allSpeciesWorkTerminal =>
      imageStagesComplete &&
      speciesCommonNamesTerminalCount >= speciesCommonNamesWantedCount &&
      inatBackfillTerminalCount >= inatBackfillWantedCount &&
      taxonomyTerminalCount >= taxonomyTotalCount &&
      pendingUnresolvedNameCount == 0;

  @override
  bool operator ==(Object other) {
    return other is DeckEnrichmentProjection &&
        other.deckId == deckId &&
        other.speciesCount == speciesCount &&
        other.imageCompleteSpeciesCount == imageCompleteSpeciesCount &&
        other.imageDoneSpeciesCount == imageDoneSpeciesCount &&
        other.speciesCommonNamesWantedCount == speciesCommonNamesWantedCount &&
        other.speciesCommonNamesTerminalCount ==
            speciesCommonNamesTerminalCount &&
        other.inatBackfillWantedCount == inatBackfillWantedCount &&
        other.inatBackfillTerminalCount == inatBackfillTerminalCount &&
        other.taxonomyTotalCount == taxonomyTotalCount &&
        other.taxonomyTerminalCount == taxonomyTerminalCount &&
        other.pendingUnresolvedNameCount == pendingUnresolvedNameCount &&
        other.wantsInatPhotosSpeciesCount == wantsInatPhotosSpeciesCount &&
        other.wantsCommonNamesSpeciesCount == wantsCommonNamesSpeciesCount &&
        other.anyPermanentFailure == anyPermanentFailure &&
        other.anyImagePermanentFailure == anyImagePermanentFailure &&
        other.hasImmediatePendingWork == hasImmediatePendingWork &&
        other.earliestRetryAt == earliestRetryAt;
  }

  @override
  int get hashCode => Object.hash(
    deckId,
    speciesCount,
    imageCompleteSpeciesCount,
    imageDoneSpeciesCount,
    speciesCommonNamesWantedCount,
    speciesCommonNamesTerminalCount,
    inatBackfillWantedCount,
    inatBackfillTerminalCount,
    taxonomyTotalCount,
    taxonomyTerminalCount,
    Object.hash(
      pendingUnresolvedNameCount,
      wantsInatPhotosSpeciesCount,
      wantsCommonNamesSpeciesCount,
      anyPermanentFailure,
      anyImagePermanentFailure,
      hasImmediatePendingWork,
      earliestRetryAt,
    ),
  );

  @override
  String toString() =>
      'DeckEnrichmentProjection(deckId: $deckId, speciesCount: $speciesCount, '
      'imageCompleteSpeciesCount: $imageCompleteSpeciesCount, '
      'imageDoneSpeciesCount: $imageDoneSpeciesCount, '
      'speciesCommonNamesWantedCount: $speciesCommonNamesWantedCount, '
      'speciesCommonNamesTerminalCount: $speciesCommonNamesTerminalCount, '
      'inatBackfillWantedCount: $inatBackfillWantedCount, '
      'inatBackfillTerminalCount: $inatBackfillTerminalCount, '
      'taxonomyTotalCount: $taxonomyTotalCount, '
      'taxonomyTerminalCount: $taxonomyTerminalCount, '
      'pendingUnresolvedNameCount: $pendingUnresolvedNameCount, '
      'wantsInatPhotosSpeciesCount: $wantsInatPhotosSpeciesCount, '
      'wantsCommonNamesSpeciesCount: $wantsCommonNamesSpeciesCount, '
      'anyPermanentFailure: $anyPermanentFailure, '
      'anyImagePermanentFailure: $anyImagePermanentFailure, '
      'hasImmediatePendingWork: $hasImmediatePendingWork, '
      'earliestRetryAt: $earliestRetryAt)';
}
