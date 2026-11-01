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

  /// The catalog entry's subdecks, its names resolved the same way. A deck
  /// that follows its catalog entry takes them whatever the update does to
  /// the species, so it is divided up the way the entry is; for one with
  /// [hasCustomizedSubdecks] that is the user's choice.
  final SubdeckStructure subdecks;

  /// Whether the user changed how the deck is divided into subdecks.
  final bool hasCustomizedSubdecks;

  const DeckUpdateDiff({
    required this.addedSpecies,
    required this.removedSpecies,
    required this.unresolvedAddedNames,
    this.subdecks = SubdeckStructure.none,
    this.hasCustomizedSubdecks = false,
  });

  bool get hasChanges => addedSpecies.isNotEmpty || removedSpecies.isNotEmpty;
}
