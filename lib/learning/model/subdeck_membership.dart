/// How a deck's species lie in its subdecks, and what follows from it for
/// switching them on and off — the rules the edit page's subdeck switches
/// and the merge dialog's subdeck choice share.
class SubdeckMembership {
  /// How many species each subdeck holds; a subdeck holding none is missing.
  final Map<String, int> speciesCounts;

  /// Whether a species belongs to no subdeck — such a species is a card
  /// whichever subdecks are switched off.
  final bool hasSpeciesOutsideSubdecks;

  const SubdeckMembership._({
    required this.speciesCounts,
    required this.hasSpeciesOutsideSubdecks,
  });

  /// The membership of [speciesIds] by [subdeckIdBySpeciesId]; a species
  /// missing there belongs to no subdeck, and an entry for a species not in
  /// [speciesIds] counts for nothing.
  factory SubdeckMembership.of(
    Iterable<String> speciesIds,
    Map<String, String> subdeckIdBySpeciesId,
  ) {
    final counts = <String, int>{};
    var outside = false;
    for (final id in speciesIds) {
      final subdeckId = subdeckIdBySpeciesId[id];
      if (subdeckId == null) {
        outside = true;
      } else {
        counts[subdeckId] = (counts[subdeckId] ?? 0) + 1;
      }
    }
    return SubdeckMembership._(
      speciesCounts: counts,
      hasSpeciesOutsideSubdecks: outside,
    );
  }

  /// Whether a species is a card while [activeSubdeckIds] are on: one outside
  /// the subdecks, or one in a subdeck that is on.
  bool hasCardWith(Set<String> activeSubdeckIds) =>
      hasSpeciesOutsideSubdecks ||
      activeSubdeckIds.any(speciesCounts.containsKey);

  /// Whether [subdeckId] may be switched off while [activeSubdeckIds] are
  /// on: not when the cards the deck has left are all in it. An empty subdeck
  /// holds no card to lose.
  bool canSwitchOff(String subdeckId, Set<String> activeSubdeckIds) =>
      !speciesCounts.containsKey(subdeckId) ||
      hasCardWith(activeSubdeckIds.difference({subdeckId}));
}
