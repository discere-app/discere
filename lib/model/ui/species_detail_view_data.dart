import 'classification_row_view_data.dart';
import 'species_fact_view_data.dart';
import 'species_identity_view_data.dart';
import 'species_native_region_view_data.dart';

class SpeciesDetailViewData {
  final SpeciesIdentityViewData identity;
  final bool isDeprecated;
  final List<ClassificationRowViewData> classificationRows;
  final List<SpeciesFactViewData> facts;
  final List<String> habitatTags;
  final List<SpeciesNativeRegionViewData> nativeRegions;

  const SpeciesDetailViewData({
    required this.identity,
    required this.isDeprecated,
    required this.classificationRows,
    required this.facts,
    required this.habitatTags,
    required this.nativeRegions,
  });
}
