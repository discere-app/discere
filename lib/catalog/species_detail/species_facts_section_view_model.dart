import 'package:discere/catalog/species_detail/species_fact_view_model.dart';

class SpeciesFactsSectionViewModel {
  final String title;
  final List<SpeciesFactViewModel> facts;

  const SpeciesFactsSectionViewModel({
    required this.title,
    required this.facts,
  });
}
