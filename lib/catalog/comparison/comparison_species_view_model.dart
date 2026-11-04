import 'package:discere/catalog/common/species_facts/species_fact_view_model.dart';

/// One species of a comparison: its names, as the watchlist shows them, and
/// the few facts that help tell it from the others.
class ComparisonSpeciesViewModel {
  final String primaryName;
  final String scientificName;
  final List<SpeciesFactViewModel> facts;

  const ComparisonSpeciesViewModel({
    required this.primaryName,
    required this.scientificName,
    required this.facts,
  });
}
