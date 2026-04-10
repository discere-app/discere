class SpeciesNativeRegionViewData {
  final bool isSubregion;
  final String label;
  final String? secondary;

  const SpeciesNativeRegionViewData({
    required this.isSubregion,
    required this.label,
    this.secondary,
  });
}
