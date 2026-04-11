class TaxonIdentityViewModel {
  final String primaryName;
  final String scientificName;
  final List<String> commonNames;

  const TaxonIdentityViewModel({
    required this.primaryName,
    required this.scientificName,
    required this.commonNames,
  });
}
