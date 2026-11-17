class SpeciesListItemViewModel {
  final String primaryName;
  final String scientificName;
  final String? additionalNames;
  final String? localImagePath;
  final String? remoteImageUrl;

  /// The synonym a search found this species through; `null` everywhere
  /// else.
  final String? matchedSynonym;

  const SpeciesListItemViewModel({
    required this.primaryName,
    required this.scientificName,
    required this.additionalNames,
    required this.localImagePath,
    required this.remoteImageUrl,
    required this.matchedSynonym,
  });
}
