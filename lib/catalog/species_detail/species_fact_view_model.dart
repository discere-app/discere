enum SpeciesFactType {
  size,
  depth,
  habitat,
  conservation,
  bodyForm,
  humanRisk,
  fishingImportance,
  typicalLifespan,
  foodChainLevel,
}

class SpeciesFactViewModel {
  final SpeciesFactType type;
  final String label;
  final String value;

  const SpeciesFactViewModel({
    required this.type,
    required this.label,
    required this.value,
  });
}
