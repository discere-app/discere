import 'package:discere/catalog/species_detail/species_native_region_view_model.dart';

class SpeciesNativeRegionsSectionViewModel {
  final String title;
  final List<SpeciesNativeRegionViewModel> nativeRegions;
  final List<String> habitatTags;
  final List<String> continents;

  const SpeciesNativeRegionsSectionViewModel({
    required this.title,
    required this.nativeRegions,
    required this.habitatTags,
    this.continents = const [],
  });
}
