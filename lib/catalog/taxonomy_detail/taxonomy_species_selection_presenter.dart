import 'package:discere/catalog/model/region_abundance.dart';
import 'package:discere/catalog/model/search_result.dart';

/// Pure filter/sort logic for [TaxonomySpeciesSelectionPage], kept free of
/// BuildContext/Future state so it can be unit tested directly.
class TaxonomySpeciesSelectionPresenter {
  const TaxonomySpeciesSelectionPresenter();

  /// With no region filter active, returns [species] sorted alphabetically.
  ///
  /// With a region filter active, [abundanceRawValuesBySpeciesId] reflects
  /// `TaxonomyRepository.getAbundanceRawValuesByRegion`: species absent from
  /// it don't occur in any selected region and are dropped; species present
  /// in it are kept and sorted by [bestAbundanceFor] (most frequently
  /// sighted first, species with no rating last), alphabetically within a
  /// tier.
  List<SearchResult> filterAndSort(
    List<SearchResult> species, {
    required bool regionFilterActive,
    Map<String, List<String>> abundanceRawValuesBySpeciesId = const {},
  }) {
    if (!regionFilterActive) {
      final sorted = [...species];
      sorted.sort((a, b) => a.name.compareTo(b.name));
      return sorted;
    }

    final filtered = species
        .where((s) => abundanceRawValuesBySpeciesId.containsKey(s.id))
        .toList();
    filtered.sort((a, b) {
      final tierComparison = _tierFor(
        bestAbundanceFor(abundanceRawValuesBySpeciesId[a.id] ?? const []),
      ).compareTo(
        _tierFor(
          bestAbundanceFor(abundanceRawValuesBySpeciesId[b.id] ?? const []),
        ),
      );
      if (tierComparison != 0) return tierComparison;
      return a.name.compareTo(b.name);
    });
    return filtered;
  }

  /// The most frequently-sighted [RegionAbundance] parsed out of a species'
  /// raw abundance values across the selected regions, or null if none of
  /// them parse (including when the list is empty — present, but unrated).
  RegionAbundance? bestAbundanceFor(List<String> rawValues) {
    RegionAbundance? best;
    for (final raw in rawValues) {
      final parsed = RegionAbundance.fromRaw(raw);
      if (parsed == null) continue;
      if (best == null || _tierFor(parsed) < _tierFor(best)) {
        best = parsed;
      }
    }
    return best;
  }

  int _tierFor(RegionAbundance? abundance) {
    if (abundance == null) return RegionAbundance.tiers.length;
    return RegionAbundance.tiers.indexOf(abundance);
  }
}
