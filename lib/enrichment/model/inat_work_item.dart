/// A single unit of rate-limited iNaturalist work, claimed from the shared
/// priority queue spanning `enrichment_species_capability_state`,
/// `enrichment_taxonomy_work`, and `enrichment_unresolved_names`.
///
/// See `EnrichmentWorkRepository.claimNextINatWorkItem` — the queue is a
/// single priority order across all five kinds (P10 inatPrimary < P20
/// speciesCommonNames < P30 taxonomyCommonNames < P40 inatBackfill < P50
/// nameResolution), so exactly one rate-limited consumer can drain all of
/// them without needing to know which table a given item came from.
enum INatWorkItemKind {
  inatPrimary,
  speciesCommonNames,
  taxonomyCommonNames,
  inatBackfill,
  nameResolution,
}

class INatWorkItem {
  final INatWorkItemKind kind;
  final String? speciesId;
  final String? taxonomyWorkKey;
  final String? taxonomyRuntimeEntityKey;
  final Set<String>? taxonomySpeciesIds;
  final String? deckId;
  final String? unresolvedName;

  /// Consent captured on `enrichment_unresolved_names` at the time this name
  /// was submitted for resolution — only meaningful for
  /// [INatWorkItemKind.nameResolution] items. A resolved species is
  /// registered with exactly this consent (see
  /// `EnrichmentWorkRepository.registerResolvedSpeciesForDeck`), not a
  /// hardcoded default, so a deck that opted out of iNat enrichment doesn't
  /// end up granting it anyway just because one of its species names needed
  /// a resolution round-trip.
  final bool wantsInatPhotos;
  final bool wantsCommonNames;

  /// The priority tier this item was claimed at (0/10/20/30/40/50 — lower is
  /// more urgent). Purely informational by the time the item reaches here —
  /// `claimNextINatWorkItem`'s ordering already made the selection decision;
  /// nothing about processing the item depends on this value. Kept around
  /// for logging/diagnostics only.
  final int priorityTier;

  const INatWorkItem._({
    required this.kind,
    required this.priorityTier,
    this.speciesId,
    this.taxonomyWorkKey,
    this.taxonomyRuntimeEntityKey,
    this.taxonomySpeciesIds,
    this.deckId,
    this.unresolvedName,
    this.wantsInatPhotos = false,
    this.wantsCommonNames = false,
  });

  const INatWorkItem.species(
    INatWorkItemKind kind,
    String speciesId, {
    required int priorityTier,
  }) : this._(kind: kind, priorityTier: priorityTier, speciesId: speciesId);

  /// [speciesIds] is the full set of species this taxonomy entity's common
  /// names apply to (needed by
  /// `TaxonomyCommonNameEnrichmentService.fetchINatTaxonomyCommonNamesForEntityKeys`
  /// to re-derive the taxonomy target from species classifications) —
  /// distinct from [workKey] (`rank:taxon:<id>` once a taxon id is known,
  /// else the runtime entity key) and [runtimeEntityKey] (always
  /// `rank:<scientificName>`, the key the fetch call itself is keyed on).
  const INatWorkItem.taxonomy(
    String workKey,
    String runtimeEntityKey,
    Set<String> speciesIds,
  ) : this._(
        kind: INatWorkItemKind.taxonomyCommonNames,
        priorityTier: 30,
        taxonomyWorkKey: workKey,
        taxonomyRuntimeEntityKey: runtimeEntityKey,
        taxonomySpeciesIds: speciesIds,
      );

  const INatWorkItem.nameResolution(
    String deckId,
    String name, {
    required bool wantsInatPhotos,
    required bool wantsCommonNames,
  }) : this._(
         kind: INatWorkItemKind.nameResolution,
         priorityTier: 50,
         deckId: deckId,
         unresolvedName: name,
         wantsInatPhotos: wantsInatPhotos,
         wantsCommonNames: wantsCommonNames,
       );

  @override
  String toString() =>
      'INatWorkItem(kind: $kind, priorityTier: $priorityTier, '
      'speciesId: $speciesId, taxonomyWorkKey: $taxonomyWorkKey, '
      'taxonomyRuntimeEntityKey: $taxonomyRuntimeEntityKey, '
      'taxonomySpeciesIds: $taxonomySpeciesIds, deckId: $deckId, '
      'unresolvedName: $unresolvedName, wantsInatPhotos: $wantsInatPhotos, '
      'wantsCommonNames: $wantsCommonNames)';
}
