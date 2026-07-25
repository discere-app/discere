import 'package:discere/catalog/model/region_abundance.dart';
import 'package:discere/catalog/model/search_result.dart';

/// Pure filter/sort logic for [TaxonomySpeciesSelectionPage], kept free of
/// BuildContext/Future state so it can be unit tested directly.
class TaxonomySpeciesSelectionPresenter {
  const TaxonomySpeciesSelectionPresenter();

  /// Every selectable value for the frequency filter: the known
  /// [RegionAbundance] tiers plus `null`, representing species that are
  /// present but have no rated abundance (or, without a region filter, no
  /// distribution data at all).
  static const Set<RegionAbundance?> allFrequencyTiers = {
    ...RegionAbundance.tiers,
    null,
  };

  /// Filters and sorts [species] along two independent, combinable
  /// dimensions:
  ///
  /// - With a region filter active, [abundanceRawValuesBySpeciesId] reflects
  ///   `TaxonomyRepository.getAbundanceRawValuesByRegion`: species absent
  ///   from it don't occur in any selected region and are dropped.
  /// - With a frequency filter active (i.e. [selectedTiers] is a strict
  ///   subset of [allFrequencyTiers]), species whose [bestAbundanceFor] tier
  ///   isn't in [selectedTiers] are dropped.
  ///
  /// The result is sorted by [bestAbundanceFor] (most frequently sighted
  /// first, unrated last) whenever either filter is active, since
  /// [abundanceRawValuesBySpeciesId] is then meaningful context for the
  /// list; otherwise it's plain alphabetical. Ties are broken alphabetically.
  List<SearchResult> filterAndSort(
    List<SearchResult> species, {
    required bool regionFilterActive,
    Map<String, List<String>> abundanceRawValuesBySpeciesId = const {},
    Set<RegionAbundance?> selectedTiers = allFrequencyTiers,
  }) {
    final frequencyFilterActive = selectedTiers.length < allFrequencyTiers.length;

    var result = species;
    if (regionFilterActive) {
      result = result
          .where((s) => abundanceRawValuesBySpeciesId.containsKey(s.id))
          .toList();
    }
    if (frequencyFilterActive) {
      result = result
          .where(
            (s) => selectedTiers.contains(
              bestAbundanceFor(abundanceRawValuesBySpeciesId[s.id] ?? const []),
            ),
          )
          .toList();
    }

    final sorted = [...result];
    if (regionFilterActive || frequencyFilterActive) {
      sorted.sort((a, b) {
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
    } else {
      sorted.sort((a, b) => a.name.compareTo(b.name));
    }
    return sorted;
  }

  /// The most frequently-sighted [RegionAbundance] parsed out of a species'
  /// raw abundance values across the selected regions, or null if none of
  /// them parse (including when the list is empty — present, but unrated).
  RegionAbundance? bestAbundanceFor(List<String> rawValues) =>
      RegionAbundance.best(rawValues);

  int _tierFor(RegionAbundance? abundance) {
    if (abundance == null) return RegionAbundance.tiers.length;
    return RegionAbundance.tiers.indexOf(abundance);
  }
}
