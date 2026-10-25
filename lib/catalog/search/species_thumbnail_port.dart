/// Where a species list gets the thumbnail of one of its rows.
///
/// Declared here, where `SearchResultThumbnail` consumes it, and implemented
/// in `enrichment`, which knows where iNaturalist photos come from and when
/// a taxon may be trusted to show a species.
abstract interface class SpeciesThumbnailPort {
  /// A remote image URL for the species [speciesId], or null when it has
  /// none to show. Never throws: a thumbnail is decoration, so every failure
  /// ends in the placeholder rather than an error.
  Future<String?> thumbnailUrl(String speciesId);
}
