class TaxonomyClassificationRowViewModel {
  final String label;
  final String scientificName;
  final String? commonName;

  const TaxonomyClassificationRowViewModel({
    required this.label,
    required this.scientificName,
    this.commonName,
  });
}
