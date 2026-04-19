abstract class DeckSpeciesSnapshotPort {
  Future<Set<String>> loadSpeciesIdsForDecks(Set<String> deckIds);
}

abstract class DeckCoverStorePort {
  Future<void> updateDeckCoverPath(String deckId, String localPath);
}

abstract class DeckSpeciesMutationPort {
  Future<void> addSpeciesToDeck(String deckId, Set<String> speciesIds);
}

abstract class ScientificNameResolutionPort {
  Future<Map<String, String>> resolveNames(List<String> names);
}

abstract class UnresolvedNamesObserverPort {
  void onNamesUnresolved(String deckId, List<String> stillUnresolved);
}
