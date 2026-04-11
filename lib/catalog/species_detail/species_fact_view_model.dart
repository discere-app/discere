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

enum SpeciesFactTone { neutral, safe, caution, warning, danger }

class SpeciesFactViewModel {
  final SpeciesFactType type;
  final String label;
  final String value;
  final SpeciesFactTone tone;

  const SpeciesFactViewModel({
    required this.type,
    required this.label,
    required this.value,
    this.tone = SpeciesFactTone.neutral,
  });
}
