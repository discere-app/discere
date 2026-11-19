/// Where a list gets the thumbnail of a genus, family, order or class row.
///
/// Declared here, where `SearchResultThumbnail` consumes it, and implemented
/// in `enrichment`, which knows where iNaturalist photos come from and when
/// a taxon may be trusted to show a higher rank.
abstract interface class HigherTaxonThumbnailPort {
  /// A remote image URL for the taxon under [entityKey] — its name key from
  /// `TaxonRank.entityKey`, e.g. `genus:massaria`, under which its
  /// iNaturalist id is kept — or null when it has none to show. Never
  /// throws: a thumbnail is decoration, so every failure ends in the
  /// placeholder rather than an error.
  Future<String?> thumbnailUrl(String entityKey);
}
