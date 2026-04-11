import 'package:discere/catalog/common/taxon_classification/classification_row_view_model.dart';
import 'package:discere/catalog/common/taxon_identity/taxon_identity_view_model.dart';
import 'package:discere/catalog/species_detail/species_facts_section_view_model.dart';
import 'package:discere/catalog/species_detail/species_native_regions_section_view_model.dart';

class SpeciesDetailViewModel {
  final TaxonIdentityViewModel identity;
  final bool isDeprecated;
  final List<ClassificationRowViewModel> classificationRows;
  final SpeciesFactsSectionViewModel factsSection;
  final SpeciesNativeRegionsSectionViewModel? nativeRegionsSection;

  const SpeciesDetailViewModel({
    required this.identity,
    required this.isDeprecated,
    required this.classificationRows,
    required this.factsSection,
    required this.nativeRegionsSection,
  });
}
