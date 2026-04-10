class SpeciesNativeRegion {
  final String scope;
  final String label;
  final String? presenceStatus;
  final String? establishmentStatus;
  final String? abundance;
  final String? importance;
  final bool isThreatened;
  final String? comment;

  const SpeciesNativeRegion({
    required this.scope,
    required this.label,
    this.presenceStatus,
    this.establishmentStatus,
    this.abundance,
    this.importance,
    this.isThreatened = false,
    this.comment,
  });
}
