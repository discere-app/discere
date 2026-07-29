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
  final String? deckId;
  final String? unresolvedName;

  /// The priority tier this item was claimed at (0/10/20/30/40/50 — lower is
  /// more urgent). Purely informational by the time the item reaches here —
  /// `claimNextINatWorkItem`'s `ORDER BY priority_tier` already made the
  /// selection decision; nothing about processing the item depends on this
  /// value. Kept around for logging/diagnostics only.
  final int priorityTier;

  const INatWorkItem._({
    required this.kind,
    required this.priorityTier,
    this.speciesId,
    this.taxonomyWorkKey,
    this.deckId,
    this.unresolvedName,
  });

  const INatWorkItem.species(
    INatWorkItemKind kind,
    String speciesId, {
    required int priorityTier,
  }) : this._(kind: kind, priorityTier: priorityTier, speciesId: speciesId);

  const INatWorkItem.taxonomy(String workKey, {required int priorityTier})
    : this._(
        kind: INatWorkItemKind.taxonomyCommonNames,
        priorityTier: priorityTier,
        taxonomyWorkKey: workKey,
      );

  const INatWorkItem.nameResolution(
    String deckId,
    String name, {
    required int priorityTier,
  }) : this._(
         kind: INatWorkItemKind.nameResolution,
         priorityTier: priorityTier,
         deckId: deckId,
         unresolvedName: name,
       );

  @override
  String toString() =>
      'INatWorkItem(kind: $kind, priorityTier: $priorityTier, '
      'speciesId: $speciesId, taxonomyWorkKey: $taxonomyWorkKey, '
      'deckId: $deckId, unresolvedName: $unresolvedName)';
}
