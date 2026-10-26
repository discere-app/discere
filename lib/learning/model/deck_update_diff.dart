import 'package:discere/catalog/model/species.dart';
import 'package:discere/learning/model/subdeck_structure.dart';

/// Difference between a locally-imported deck's current species and the
/// species listed by its online catalog entry, computed by
/// [DeckImportService.diffForUpdate].
class DeckUpdateDiff {
  final List<Species> addedSpecies;
  final List<Species> removedSpecies;

  /// Catalog species names that aren't resolvable in the local taxonomy yet
  /// (same best-effort handling as a fresh import).
  final List<String> unresolvedAddedNames;

  /// The catalog entry's subdecks, its names resolved the same way. Not a
  /// change the user picks: an update applies them whatever it does to the
  /// species, so the deck is divided up the way its catalog entry is.
  final SubdeckStructure subdecks;

  const DeckUpdateDiff({
    required this.addedSpecies,
    required this.removedSpecies,
    required this.unresolvedAddedNames,
    this.subdecks = SubdeckStructure.none,
  });

  bool get hasChanges => addedSpecies.isNotEmpty || removedSpecies.isNotEmpty;
}
