class SpeciesNativeRegionViewModel {
  final String label;
  final List<String> subregions;
  final bool isEndemic;

  const SpeciesNativeRegionViewModel({
    required this.label,
    this.subregions = const [],
    this.isEndemic = false,
  });
}
