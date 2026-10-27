abstract class DeckSpeciesSnapshotPort {
  /// The species of each of [deckIds], keyed by deck id. A deck without
  /// species may be missing from the result.
  Future<Map<String, Set<String>>> loadSpeciesIdsByDeckId(Set<String> deckIds);
}

abstract class DeckCoverStorePort {
  Future<void> updateDeckCoverPath(String deckId, String localPath);
}

abstract class DeckSpeciesMutationPort {
  /// Adds [speciesId], which the name [resolvedName] of [deckId] resolved
  /// to, to that deck. The name goes along because the deck may have more
  /// to say about where a species listed under it belongs.
  Future<void> addResolvedSpeciesToDeck(
    String deckId,
    String speciesId, {
    required String resolvedName,
  });
}

abstract class ScientificNameResolutionPort {
  Future<Map<String, String>> resolveNames(List<String> names);
}

abstract class UnresolvedNamesObserverPort {
  void onNamesUnresolved(String deckId, List<String> stillUnresolved);
}

abstract class AllDeckIdsPort {
  Future<Set<String>> loadAllDeckIds();
}
