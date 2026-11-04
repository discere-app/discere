/// A species just taken out of a comparison list, with what it takes to put
/// it back where it was.
class RemovedComparisonSpecies {
  final String listId;
  final String speciesId;

  /// Its place in the list, which putting it back restores.
  final int position;

  const RemovedComparisonSpecies({
    required this.listId,
    required this.speciesId,
    required this.position,
  });
}
