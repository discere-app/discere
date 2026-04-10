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

class SpeciesFactViewData {
  final SpeciesFactType type;
  final String value;

  const SpeciesFactViewData({required this.type, required this.value});
}
