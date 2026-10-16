import 'package:discere/catalog/model/taxon_rank.dart';
import 'package:discere/shared/model/language.dart';

/// A species' chain of higher ranks.
///
/// The chain can break off: a reference database may hold a species without
/// a genus, or a genus without a family. The rank where it breaks and every
/// rank above it have no taxon, so their names and ids are `null` — not an
/// empty string, which would pass for a name in a query, a link or an
/// answer.
class Classification {
  final String? genusId;
  final String? genusScientificName;
  final Map<Language, List<String>> genusCommonNames;
  final String? subFamily;
  final String? familyId;
  final String? familyScientificName;
  final Map<Language, List<String>> familyCommonNames;
  final String? orderId;
  final String? orderScientificName;
  final Map<Language, List<String>> orderCommonNames;
  final String? classId;
  final String? classScientificName;
  final Map<Language, List<String>> classCommonNames;
  final String? superClass;

  /// The ranks of this chain that are a source's rank placeholder ("Not
  /// assigned") rather than a taxon. Such a rank keeps its id, so it can be
  /// navigated to, but has no name worth showing or asking for.
  final Set<TaxonRank> placeholderRanks;

  Classification(
    this.genusScientificName,
    this.genusCommonNames,
    this.subFamily,
    this.familyScientificName,
    this.familyCommonNames,
    this.orderScientificName,
    this.orderCommonNames,
    this.classScientificName,
    this.classCommonNames,
    this.superClass, {
    this.genusId,
    this.familyId,
    this.orderId,
    this.classId,
    this.placeholderRanks = const {},
  });

  bool isPlaceholder(TaxonRank rank) => placeholderRanks.contains(rank);

  /// The scientific name at [rank], `null` where the chain has no taxon.
  String? scientificNameAt(TaxonRank rank) => switch (rank) {
    TaxonRank.genus => genusScientificName,
    TaxonRank.family => familyScientificName,
    TaxonRank.order => orderScientificName,
    TaxonRank.classRank => classScientificName,
  };

  /// The reference id at [rank], `null` where the chain has no taxon.
  String? idAt(TaxonRank rank) => switch (rank) {
    TaxonRank.genus => genusId,
    TaxonRank.family => familyId,
    TaxonRank.order => orderId,
    TaxonRank.classRank => classId,
  };

  /// Whether [rank] assigns the species to no taxon: a placeholder, or no
  /// rank at all because the chain breaks off below it. Both read the same
  /// to a user — "not assigned" — and neither is a name to ask for.
  bool isUnassigned(TaxonRank rank) =>
      isPlaceholder(rank) || scientificNameAt(rank) == null;

  Set<TaxonRank> get unassignedRanks => {
    for (final rank in TaxonRank.values)
      if (isUnassigned(rank)) rank,
  };
}
