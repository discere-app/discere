/// What a taxon found by a name search must have in its ancestry to count as
/// the taxon meant.
///
/// A name alone does not tell homonyms apart: the snail *Triphora pusilla*
/// shares its name with an orchid, and a search finds whichever iNaturalist
/// has. The reference data says which phyla (and classes) fit the taxon
/// asked about; a hit fits when its `ancestor_ids` name one of each.
///
/// Every entry of [anyOf] lists alternatives — the iNaturalist ids of the
/// phyla an own phylum corresponds to, say — and a hit needs at least one id
/// of every entry. Several entries come from a name several own taxa carry,
/// or from checking the class besides the phylum.
final class INatAncestryRequirement {
  final List<Set<int>> anyOf;

  const INatAncestryRequirement(this.anyOf);

  /// Whether any hit could meet it. Not when there is nothing to check
  /// against — a species without a chain up to its class, a placeholder
  /// phylum — and a hit that cannot be checked is not taken.
  bool get canBeMet =>
      anyOf.isNotEmpty && anyOf.every((alternatives) => alternatives.isNotEmpty);

  /// Whether a hit with [ancestorIds] fits. The search answers a taxon's
  /// ancestry including the taxon itself.
  bool isMetBy(Iterable<int> ancestorIds) {
    if (!canBeMet) return false;
    final ancestors = ancestorIds.toSet();
    return anyOf.every((alternatives) => alternatives.any(ancestors.contains));
  }
}
