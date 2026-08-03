import 'package:discere/catalog/model/search_result.dart';

/// The four higher taxonomy ranks the app enriches and searches beyond
/// species: genus, family, order, class. Centralizes the rank ↔
/// string-representation mappings that used to be hand-copied `switch`
/// statements across catalog/enrichment repositories and services — each
/// mapping only needs to be correct once, here.
enum TaxonRank {
  genus,
  family,
  order,
  // 'class' is a reserved word in Dart.
  classRank;

  /// Singular rank name as used in ETL rank columns, entity-key prefixes,
  /// and the iNaturalist API's `rank` parameter (e.g. `'genus'`).
  String get rankName => switch (this) {
    TaxonRank.genus => 'genus',
    TaxonRank.family => 'family',
    TaxonRank.order => 'order',
    TaxonRank.classRank => 'class',
  };

  /// Plural "entity type" as used for `search_results.entity_type` and the
  /// reference-DB table name for this rank (e.g. `'genera'`).
  String get entityType => switch (this) {
    TaxonRank.genus => 'genera',
    TaxonRank.family => 'families',
    TaxonRank.order => 'orders',
    TaxonRank.classRank => 'classes',
  };

  /// Reference-DB table name for this rank. Identical to [entityType] for
  /// all four ranks, but named separately so call sites reading "which
  /// table" aren't implicitly reasoning about search entity types.
  String get referenceTableName => entityType;

  /// Parses a singular rank name (see [rankName]), or null if [rank] isn't
  /// one of the four higher ranks (e.g. `'species'`).
  static TaxonRank? fromRankName(String? rank) => switch (rank) {
    'genus' => TaxonRank.genus,
    'family' => TaxonRank.family,
    'order' => TaxonRank.order,
    'class' => TaxonRank.classRank,
    _ => null,
  };

  /// Parses a plural entity type (see [entityType]), or null if
  /// [entityType] isn't one of the four higher ranks (e.g. `'species'`).
  static TaxonRank? fromEntityType(String? entityType) => switch (entityType) {
    'genera' => TaxonRank.genus,
    'families' => TaxonRank.family,
    'orders' => TaxonRank.order,
    'classes' => TaxonRank.classRank,
    _ => null,
  };

  /// Converts a [SearchEntityType], throwing if it's [SearchEntityType.species]
  /// — species aren't a higher taxonomy rank.
  static TaxonRank fromSearchEntityType(SearchEntityType type) =>
      switch (type) {
        SearchEntityType.genus => TaxonRank.genus,
        SearchEntityType.family => TaxonRank.family,
        SearchEntityType.order => TaxonRank.order,
        SearchEntityType.classType => TaxonRank.classRank,
        SearchEntityType.species => throw ArgumentError(
          'Species are not a higher taxonomy rank.',
        ),
      };

  /// The runtime-common-name/work-queue entity key for [scientificName] at
  /// this rank, e.g. `genus:barbus`.
  String entityKey(String scientificName) =>
      '$rankName:${scientificName.trim().toLowerCase()}';
}
