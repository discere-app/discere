import 'package:discere/catalog/model/iucn_status.dart';
import 'package:discere/catalog/model/search_result.dart';

/// Pure sort logic for [TaxonomySpeciesSelectionPage], kept free of
/// BuildContext/Future state so it can be unit tested directly.
class TaxonomySpeciesSelectionPresenter {
  const TaxonomySpeciesSelectionPresenter();

  /// Sorts [species] alphabetically by default. When [byRarity] is true,
  /// orders by IUCN threat severity instead (extinct first, least concern
  /// last on the threat spectrum), then data-deficient/not-evaluated species,
  /// then species with no cached status at all — alphabetically within each
  /// tier.
  List<SearchResult> sort(
    List<SearchResult> species,
    Map<String, IucnStatus> statusById, {
    required bool byRarity,
  }) {
    final sorted = [...species];
    if (!byRarity) {
      sorted.sort((a, b) => a.name.compareTo(b.name));
      return sorted;
    }

    sorted.sort((a, b) {
      final tierComparison = _tierFor(
        statusById[a.id],
      ).compareTo(_tierFor(statusById[b.id]));
      if (tierComparison != 0) return tierComparison;
      return a.name.compareTo(b.name);
    });
    return sorted;
  }

  int _tierFor(IucnStatus? status) {
    if (status == null) return IucnStatus.threatSpectrum.length + 1;
    final spectrumIndex = IucnStatus.threatSpectrum.indexOf(status);
    if (spectrumIndex >= 0) return spectrumIndex;
    return IucnStatus.threatSpectrum.length;
  }
}
