/// Decides which deck's species get enriched first when several are
/// scheduled at once.
///
/// Species are deduplicated across decks: one species is owned by exactly
/// one deck's work, and every other deck referencing it rides along. So the
/// deck to start with is the one whose species are shared the most — doing
/// it first makes the most other decks reviewable soonest. A deck of
/// entirely unique species helps only itself and can wait.
library;

/// [deckIds] ordered by how much of the whole batch each deck covers.
///
/// A deck scores the sum, over its species, of how many decks in the batch
/// contain that species — so a species in three decks contributes three to
/// each of them. Ties keep the caller's order, which is the order the user
/// created or imported the decks in.
List<String> prioritizeDecksBySharedSpecies(
  List<String> deckIds,
  Map<String, Set<String>> speciesIdsByDeckId,
) {
  final frequency = <String, int>{};
  for (final deckId in deckIds) {
    for (final speciesId in speciesIdsByDeckId[deckId] ?? const <String>{}) {
      frequency.update(speciesId, (count) => count + 1, ifAbsent: () => 1);
    }
  }

  final originalOrder = <String, int>{
    for (var index = 0; index < deckIds.length; index++) deckIds[index]: index,
  };

  int scoreOf(String deckId) =>
      (speciesIdsByDeckId[deckId] ?? const <String>{}).fold<int>(
        0,
        (score, speciesId) => score + (frequency[speciesId] ?? 0),
      );

  return deckIds.toList(growable: false)..sort((left, right) {
    final byScore = scoreOf(right).compareTo(scoreOf(left));
    if (byScore != 0) return byScore;
    return (originalOrder[left] ?? 0).compareTo(originalOrder[right] ?? 0);
  });
}
