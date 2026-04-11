class SpeciesListItemViewModel {
  final String primaryName;
  final String scientificName;
  final String? additionalNames;
  final String? localImagePath;
  final String? remoteImageUrl;

  const SpeciesListItemViewModel({
    required this.primaryName,
    required this.scientificName,
    required this.additionalNames,
    required this.localImagePath,
    required this.remoteImageUrl,
  });
}
