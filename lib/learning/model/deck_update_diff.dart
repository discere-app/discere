import 'package:discere/catalog/model/species.dart';

/// Difference between a locally-imported deck's current species and the
/// species listed by its online catalog entry, computed by
/// [DeckImportService.diffForUpdate].
class DeckUpdateDiff {
  final List<Species> addedSpecies;
  final List<Species> removedSpecies;

  /// Catalog species names that aren't resolvable in the local taxonomy yet
  /// (same best-effort handling as a fresh import).
  final List<String> unresolvedAddedNames;

  const DeckUpdateDiff({
    required this.addedSpecies,
    required this.removedSpecies,
    required this.unresolvedAddedNames,
  });

  bool get hasChanges => addedSpecies.isNotEmpty || removedSpecies.isNotEmpty;
}
