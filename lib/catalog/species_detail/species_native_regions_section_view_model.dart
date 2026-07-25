import 'package:discere/catalog/model/region_abundance.dart';
import 'package:discere/catalog/species_detail/species_native_region_view_model.dart';

class SpeciesNativeRegionsSectionViewModel {
  final String title;
  final List<SpeciesNativeRegionViewModel> nativeRegions;
  final List<String> habitatTags;
  final List<String> continents;

  /// The most frequently-sighted tier across [nativeRegions], or null when
  /// there's distribution data but none of it carries a rated abundance.
  /// Only meaningful when [nativeRegions] is non-empty.
  final RegionAbundance? bestAbundance;

  const SpeciesNativeRegionsSectionViewModel({
    required this.title,
    required this.nativeRegions,
    required this.habitatTags,
    this.continents = const [],
    this.bestAbundance,
  });
}
