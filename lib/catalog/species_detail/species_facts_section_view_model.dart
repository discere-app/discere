import 'package:discere/catalog/common/species_facts/species_fact_view_model.dart';

class SpeciesFactsSectionViewModel {
  final String title;
  final List<SpeciesFactViewModel> facts;

  const SpeciesFactsSectionViewModel({
    required this.title,
    required this.facts,
  });
}
