class TaxonIdentityViewModel {
  final String primaryName;
  final String scientificName;
  final List<String> commonNames;

  /// Whether [primaryName]/[commonNames] are an English fallback because
  /// the requested language had no common name for this taxon.
  final bool isEnglishFallback;

  const TaxonIdentityViewModel({
    required this.primaryName,
    required this.scientificName,
    required this.commonNames,
    required this.isEnglishFallback,
  });
}
