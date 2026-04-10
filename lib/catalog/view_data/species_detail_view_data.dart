import 'classification_row_view_data.dart';
import 'species_fact_view_data.dart';
import 'species_identity_view_data.dart';
import 'species_native_region_view_data.dart';

class SpeciesDetailViewData {
  final SpeciesIdentityViewData identity;
  final bool isDeprecated;
  final List<ClassificationRowViewData> classificationRows;
  final SpeciesFactsSectionViewData factsSection;
  final SpeciesNativeRegionsSectionViewData? nativeRegionsSection;

  const SpeciesDetailViewData({
    required this.identity,
    required this.isDeprecated,
    required this.classificationRows,
    required this.factsSection,
    required this.nativeRegionsSection,
  });
}

class SpeciesFactsSectionViewData {
  final String title;
  final String habitatTitle;
  final List<SpeciesFactViewData> facts;
  final List<String> habitatTags;

  const SpeciesFactsSectionViewData({
    required this.title,
    required this.habitatTitle,
    required this.facts,
    required this.habitatTags,
  });
}

class SpeciesNativeRegionsSectionViewData {
  final String title;
  final String subtitle;
  final String moreLabelSuffix;
  final List<SpeciesNativeRegionViewData> nativeRegions;

  const SpeciesNativeRegionsSectionViewData({
    required this.title,
    required this.subtitle,
    required this.moreLabelSuffix,
    required this.nativeRegions,
  });
}
