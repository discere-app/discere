import 'package:discere/catalog/species_detail/species_fact_view_model.dart';

enum TrophicLevelCategory {
  herbivore('Herbivore', SpeciesFactTone.safe),
  omnivore('Omnivore', SpeciesFactTone.caution),
  carnivore('Carnivore', SpeciesFactTone.warning),
  apexPredator('Apex predator', SpeciesFactTone.danger);

  const TrophicLevelCategory(this.label, this.tone);

  final String label;
  final SpeciesFactTone tone;
}

TrophicLevelCategory? mapTrophicLevelCategory(double? trophicLevel) {
  if (trophicLevel == null) return null;

  // FishBase describes trophic level 2 as herbivores/detritivores, with
  // carnivorous fishes typically ranging from 3.0 to about 4.5 and the highest
  // aquatic values reaching about 5.5. We convert this to simpler UI buckets.
  // Source: https://fishbase.se/FishOnLine/english/fol_fishaspart.htm
  if (trophicLevel < 2.5) {
    return TrophicLevelCategory.herbivore;
  }
  if (trophicLevel < 3.0) {
    return TrophicLevelCategory.omnivore;
  }
  if (trophicLevel < 4.0) {
    return TrophicLevelCategory.carnivore;
  }
  return TrophicLevelCategory.apexPredator;
}

String? formatTrophicLevel(double? trophicLevel) {
  return mapTrophicLevelCategory(trophicLevel)?.label;
}
