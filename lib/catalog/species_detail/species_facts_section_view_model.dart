import 'package:discere/catalog/species_detail/species_fact_view_model.dart';

class SpeciesFactsSectionViewModel {
  final String title;
  final String habitatTitle;
  final List<SpeciesFactViewModel> facts;
  final List<String> habitatTags;

  const SpeciesFactsSectionViewModel({
    required this.title,
    required this.habitatTitle,
    required this.facts,
    required this.habitatTags,
  });
}
